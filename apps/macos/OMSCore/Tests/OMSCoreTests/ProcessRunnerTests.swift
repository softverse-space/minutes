import Foundation
import Testing
@testable import OMSCore

struct ProcessRunnerTests {
    static let shell = URL(filePath: "/bin/sh")

    private func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    private func readPID(_ file: URL) async throws -> Int32 {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: file, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CocoaError(.fileReadNoSuchFile)
    }

    @Test func collectsOutputExitCodeAndInput() async throws {
        let result = try await ProcessRunner.run(Self.shell, arguments: ["-c", "cat; echo problem >&2; exit 3"],
                                                 input: Data("hello".utf8))
        #expect(result.stdout == "hello")
        #expect(result.stderr == "problem\n")
        #expect(result.exitCode == 3)
    }

    @Test func runsInTheGivenFolder() async throws {
        let root = try TemporaryDirectory()
        let result = try await ProcessRunner.run(Self.shell, arguments: ["-c", "pwd -P"], currentDirectory: root.url)
        #expect(result.stdout.trimmingCharacters(in: .newlines).hasSuffix("/" + root.url.lastPathComponent))
    }

    @Test func aMissingExecutableIsALaunchError() async {
        await #expect(throws: ProcessRunnerError.self) {
            try await ProcessRunner.run(URL(filePath: "/nonexistent/tool"), arguments: [])
        }
    }

    @Test func anEarlyExitWithUnreadInputDoesNotKillTheCaller() async throws {
        // Without F_SETNOSIGPIPE the write to the closed pipe raises SIGPIPE in this process.
        let result = try await ProcessRunner.run(Self.shell, arguments: ["-c", "exit 0"], input: Data(count: 4 * 1024 * 1024))
        #expect(result.exitCode == 0)
    }

    @Test func cancelStopsTheProcessAndItsChildrenAndThrows() async throws {
        let root = try TemporaryDirectory()
        let parentFile = root.url.appending(path: "parent"), childFile = root.url.appending(path: "child")
        // The parent ignores SIGTERM, so only the escalation to SIGKILL can stop it. The child is a grandchild process.
        let script = "trap '' TERM; (sleep 300 & echo $! > '\(childFile.path)'; wait) & echo $$ > '\(parentFile.path)'; wait"
        let task = Task { try await ProcessRunner.run(Self.shell, arguments: ["-c", script]) }
        let parent = try await readPID(parentFile), child = try await readPID(childFile)
        #expect(isAlive(parent) && isAlive(child))

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(200))
        #expect(isAlive(parent) == false)
        #expect(isAlive(child) == false)
    }

    @Test func aTaskCancelledBeforeTheStartStillStopsTheProcess() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ProcessRunner.run(Self.shell, arguments: ["-c", "sleep 300"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func theTimeoutStopsAHangingProcess() async {
        let start = ContinuousClock.now
        await #expect(throws: ProcessRunnerError.timedOut(seconds: 1)) {
            try await ProcessRunner.run(Self.shell, arguments: ["-c", "sleep 300"], timeout: .seconds(1))
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func tooMuchOutputStopsTheProcess() async {
        await #expect(throws: ProcessRunnerError.outputTooLarge(limitBytes: 10_000)) {
            try await ProcessRunner.run(Self.shell, arguments: ["-c", "yes"], stdout: .limited(bytes: 10_000))
        }
    }

    @Test func tooMuchOutputIsAnErrorAlsoWhenTheProcessEndsFirst() async {
        // The process ends at once, so the limit is found only when the rest of the pipe is read.
        for _ in 0..<20 {
            await #expect(throws: ProcessRunnerError.outputTooLarge(limitBytes: 10_000)) {
                try await ProcessRunner.run(Self.shell, arguments: ["-c", "head -c 200000 /dev/zero"], stdout: .limited(bytes: 10_000))
            }
        }
    }

    @Test func tailKeepsTheEndOfTheOutput() async throws {
        let result = try await ProcessRunner.run(Self.shell, arguments: ["-c", "yes progress | head -c 100000; echo; echo END"],
                                                 stdout: .tail(bytes: 1_000))
        #expect(result.stdout.hasSuffix("END\n"))
        #expect(result.stdout.utf8.count <= 2_000 + 65_536)
    }

    @Test func aChildThatKeepsThePipeOpenDoesNotBlockTheResult() async throws {
        let start = ContinuousClock.now
        let result = try await ProcessRunner.run(Self.shell, arguments: ["-c", "sleep 30 & echo done"])
        #expect(result.stdout == "done\n")
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}

/// Runs the real `apps/macos/scripts/frame-at.sh`. The model calls this script, so its input checks are a safety boundary.
struct FrameToolTests {
    static let script = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../scripts/frame-at.sh").standardizedFileURL

    private func run(_ arguments: [String], in folder: URL) async throws -> ProcessResult {
        try await ProcessRunner.run(URL(filePath: "/bin/bash"), arguments: [Self.script.path] + arguments, currentDirectory: folder)
    }

    @Test(arguments: [
        [], ["00:00:01", "extra"], ["1:2:3"], ["00:61:00"], ["00:00:01; touch pwned"], ["../../etc"], ["-h"], ["00:00:01.5"],
    ] as [[String]])
    func rejectsEverythingThatIsNotOneTime(arguments: [String]) async throws {
        let root = try TemporaryDirectory()
        try Data("video".utf8).write(to: root.url.appending(path: "recording.mov"))
        let result = try await run(arguments, in: root.url)
        #expect(result.exitCode == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.path) == ["recording.mov"])
    }

    @Test func needsARecordingInTheWorkingFolder() async throws {
        let root = try TemporaryDirectory()
        let result = try await run(["00:00:01"], in: root.url)
        #expect(result.exitCode == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.path).isEmpty)
    }

    @Test func returnsAnExistingFrameAlsoFromTheFramesFolder() async throws {
        let root = try TemporaryDirectory()
        let frames = root.url.appending(path: "frames")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: root.url.appending(path: "recording.mov"))
        try Data("jpg".utf8).write(to: frames.appending(path: "at_00-07-42.jpg"))

        // Claude and OpenCode work in the session folder; Codex works in `frames`.
        for folder in [root.url, frames] {
            let result = try await run(["00:07:42"], in: folder)
            #expect(result.exitCode == 0)
            #expect(result.stdout.hasSuffix("/frames/at_00-07-42.jpg\n"))
        }
    }
    // MARK: Sessions with parts (ADR-0029)

    /// Part 1: 0–600 s, a break, part 2: 700–1000 s. Each part has a fake video.
    private func sessionWithParts(map: String = "0.000\t600.000\t01\n700.000\t300.000\t02\n") throws -> TemporaryDirectory {
        let root = try TemporaryDirectory()
        for part in ["01", "02"] {
            let folder = root.url.appending(path: "parts/\(part)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("video".utf8).write(to: folder.appending(path: "recording.mov"))
        }
        try FileManager.default.createDirectory(at: root.url.appending(path: "frames"), withIntermediateDirectories: true)
        try Data(map.utf8).write(to: root.url.appending(path: "parts.tsv"))
        return root
    }

    @Test(arguments: ["00:05:00", "00:11:40", "00:16:39"])
    func aTimeInAPartFindsItsVideo(time: String) async throws {
        let root = try sessionWithParts()
        // A cached frame: the script checks the part first and does not need ffmpeg then.
        let frame = "at_\(time.replacingOccurrences(of: ":", with: "-")).jpg"
        try Data("jpg".utf8).write(to: root.url.appending(path: "frames/\(frame)"))
        let result = try await run([time], in: root.url)
        #expect(result.exitCode == 0)
        #expect(result.stdout.hasSuffix("/frames/\(frame)\n"))
    }

    @Test(arguments: ["00:10:00", "00:11:00", "00:16:40", "01:00:00"])
    func aTimeInABreakOrAfterTheEndIsAnError(time: String) async throws {
        let root = try sessionWithParts()
        let result = try await run([time], in: root.url)
        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("break between parts"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.appending(path: "frames").path).isEmpty)
    }

    @Test(arguments: [
        "0\t600\t../../etc\n", "0\t600\t1\n", "0\t600\t01\textra\n", "x\t600\t01\n", "0;rm\t600\t01\n", "-1\t600\t01\n",
    ])
    func aDamagedMapIsAnError(map: String) async throws {
        let root = try sessionWithParts(map: map)
        let result = try await run(["00:00:01"], in: root.url)
        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("damaged"))
    }

    @Test func aPartFolderThatIsALinkIsAnError() async throws {
        let root = try sessionWithParts()
        let elsewhere = try TemporaryDirectory()
        try Data("video".utf8).write(to: elsewhere.url.appending(path: "recording.mov"))
        try FileManager.default.removeItem(at: root.url.appending(path: "parts/02"))
        try FileManager.default.createSymbolicLink(at: root.url.appending(path: "parts/02"), withDestinationURL: elsewhere.url)
        let result = try await run(["00:12:00"], in: root.url)
        #expect(result.exitCode == 1)
    }
}
