import Darwin
import Foundation

public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    /// The process did not start. The value is the system error text.
    case launchFailed(String)
    /// The process ran longer than the limit and was stopped.
    case timedOut(seconds: Int)
    /// The process wrote more to stdout than the limit and was stopped.
    case outputTooLarge(limitBytes: Int)
}

/// How much of stdout the runner keeps.
public enum OutputCapture: Sendable, Equatable {
    /// Keeps everything up to the limit. A larger output stops the process with `outputTooLarge`.
    case limited(bytes: Int)
    /// Keeps only the end of the output. Use it when stdout carries progress and not the result.
    case tail(bytes: Int)
}

public enum ProcessRunner {
    /// stderr is diagnostic text. The runner keeps only its end.
    public static let stderrTailBytes = 256 * 1024
    public static let defaultStdoutLimit = 32 * 1024 * 1024
    /// Time between SIGTERM and SIGKILL when a process is stopped.
    static let terminationGrace: TimeInterval = 3
    /// A child process can keep a pipe open after the parent ends, so the wait for end of file is limited.
    static let endOfFileGrace: TimeInterval = 2

    /// PATH for child processes. GUI apps do not get the shell PATH, so Homebrew paths are added.
    public static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.opencode/bin", "\(home)/.local/bin", "\(home)/.bun/bin"]
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return (extra + [inherited]).joined(separator: ":")
    }

    /// Finds an executable by name in `searchPath`.
    public static func which(_ name: String) -> URL? {
        for directory in searchPath.split(separator: ":") {
            let url = URL(filePath: String(directory)).appending(path: name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Runs a process in its own process group and collects stdout and stderr.
    /// `input` is written to stdin; without it stdin is empty.
    /// `onStdout` gets each chunk of stdout when it arrives, for example progress lines.
    ///
    /// Cancelling the task, the `timeout` and a too large output stop the whole process group:
    /// SIGTERM first, SIGKILL after `terminationGrace`. A cancelled run throws `CancellationError`.
    public static func run(_ executable: URL, arguments: [String], currentDirectory: URL? = nil, input: Data? = nil,
                           timeout: Duration? = nil,
                           stdout: OutputCapture = .limited(bytes: defaultStdoutLimit),
                           onStdout: (@Sendable (Data) -> Void)? = nil) async throws -> ProcessResult {
        let process = SpawnedProcess(stdout: stdout, timeout: timeout, onStdout: onStdout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                do {
                    try process.launch(executable: executable, arguments: arguments, currentDirectory: currentDirectory, input: input) {
                        continuation.resume(with: $0)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.stop(.cancelled)
        }
    }
}

/// One child process in its own process group. All state is guarded by `lock`.
private final class SpawnedProcess: @unchecked Sendable {
    enum StopReason { case cancelled, timedOut, outputTooLarge }

    private let lock = NSLock()
    private let streams = NSCondition()
    private var openStreams = 0
    private var readers: [FileHandle] = []
    private var pid: pid_t = 0
    private var hasExited = false
    private var reason: StopReason?
    private let collector: OutputCollector
    private let timeout: Duration?
    private let onStdout: (@Sendable (Data) -> Void)?

    init(stdout: OutputCapture, timeout: Duration?, onStdout: (@Sendable (Data) -> Void)?) {
        collector = OutputCollector(stdout: stdout)
        self.timeout = timeout
        self.onStdout = onStdout
    }

    func launch(executable: URL, arguments: [String], currentDirectory: URL?, input: Data?,
                completion: @escaping @Sendable (Result<ProcessResult, Error>) -> Void) throws {
        var outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1], inPipe: [Int32] = [-1, -1]
        func closeAll() { for fd in outPipe + errPipe + inPipe where fd >= 0 { close(fd) } }
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0, input == nil || pipe(&inPipe) == 0 else {
            let message = String(cString: strerror(errno))
            closeAll()
            throw ProcessRunnerError.launchFailed(message)
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if input != nil {
            posix_spawn_file_actions_adddup2(&actions, inPipe[0], STDIN_FILENO)
        } else {
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO)
        if let currentDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, currentDirectory.path)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Own process group, so one signal reaches the process and its children.
        // CLOEXEC_DEFAULT closes every descriptor in the child except stdin, stdout and stderr.
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var allSignals = sigset_t(), noSignals = sigset_t()
        sigfillset(&allSignals)
        sigemptyset(&noSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ProcessRunner.searchPath
        environment["NO_COLOR"] = "1"
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }

        // The lock is held across the spawn, so `stop` always sees either no process or a valid pid.
        lock.lock()
        var child: pid_t = 0
        let status = posix_spawn(&child, executable.path, &actions, &attributes, &argv, &envp)
        guard status == 0 else {
            lock.unlock()
            closeAll()
            throw ProcessRunnerError.launchFailed(String(cString: strerror(status)))
        }
        pid = child
        let stopBeforeStart = reason != nil
        lock.unlock()

        close(outPipe[1])
        close(errPipe[1])
        if input != nil { close(inPipe[0]) }

        read(outPipe[0], isError: false)
        read(errPipe[0], isError: true)
        if let input { Self.write(input, to: inPipe[1]) }
        if stopBeforeStart { signalGroup() }
        if let timeout {
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in self?.stop(.timedOut) }
        }
        Thread.detachNewThread { [self] in completion(waitForExit()) }
    }

    /// Stops the process group. Only the first reason counts.
    func stop(_ newReason: StopReason) {
        lock.lock()
        guard reason == nil, !hasExited else { lock.unlock(); return }
        reason = newReason
        let started = pid > 0
        lock.unlock()
        if started { signalGroup() }
    }

    /// SIGTERM now, SIGKILL after the grace period. No signal is sent after the process was reaped.
    private func signalGroup() {
        send(SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + ProcessRunner.terminationGrace) { [self] in send(SIGKILL) }
    }

    private func send(_ signal: Int32) {
        lock.lock(); defer { lock.unlock() }
        if !hasExited { kill(-pid, signal) }
    }

    private func read(_ descriptor: Int32, isError: Bool) {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        streams.lock()
        openStreams += 1
        readers.append(handle)
        streams.unlock()
        handle.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                streams.lock()
                openStreams -= 1
                streams.broadcast()
                streams.unlock()
            } else {
                if !isError { onStdout?(data) }
                if !collector.append(data, error: isError) { stop(.outputTooLarge) }
            }
        }
    }

    private static func write(_ data: Data, to descriptor: Int32) {
        // The child can end before it reads everything. Without this flag the write raises SIGPIPE in the app.
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global().async {
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count, let base = buffer.baseAddress {
                    let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
                    if written > 0 { offset += written } else if errno != EINTR { break }
                }
            }
            close(descriptor)
        }
    }

    /// Runs on its own thread until the process ends.
    private func waitForExit() -> Result<ProcessResult, Error> {
        // Wait without reaping: the pid stays reserved, so the last signal cannot reach another process.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
        lock.lock()
        let stopReason = reason
        // A stopped process can leave children behind. They are in its group.
        if stopReason != nil { kill(-pid, SIGKILL) }
        hasExited = true
        lock.unlock()

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}

        let deadline = Date().addingTimeInterval(ProcessRunner.endOfFileGrace)
        streams.lock()
        while openStreams > 0, streams.wait(until: deadline) {}
        let readers = self.readers
        self.readers = []
        streams.unlock()
        for reader in readers { reader.readabilityHandler = nil }

        // The process can end before its last output is read. `stop` ignores a limit that is found after
        // the exit, so the result comes from the collector, after the output is read.
        let reason = stopReason ?? (collector.isOverLimit ? .outputTooLarge : nil)
        switch reason {
        case .cancelled: return .failure(CancellationError())
        case .timedOut: return .failure(ProcessRunnerError.timedOut(seconds: Int(timeout?.components.seconds ?? 0)))
        case .outputTooLarge: return .failure(ProcessRunnerError.outputTooLarge(limitBytes: collector.stdoutLimit))
        case nil:
            let signal = status & 0x7f
            let (out, err) = collector.strings()
            return .success(ProcessResult(exitCode: signal == 0 ? (status >> 8) & 0xff : 128 + signal, stdout: out, stderr: err))
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let stdout: OutputCapture
    private var out = Data()
    private var err = Data()
    private var overLimit = false

    init(stdout: OutputCapture) { self.stdout = stdout }

    /// `true` when stdout was larger than its limit. The kept output is then not complete.
    var isOverLimit: Bool {
        lock.lock(); defer { lock.unlock() }
        return overLimit
    }

    var stdoutLimit: Int {
        switch stdout {
        case .limited(let bytes), .tail(let bytes): bytes
        }
    }

    /// Returns `false` when stdout is over its limit.
    func append(_ data: Data, error: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if error {
            err.append(data)
            Self.keepTail(&err, bytes: ProcessRunner.stderrTailBytes)
            return true
        }
        switch stdout {
        case .limited(let bytes):
            guard !overLimit, out.count + data.count <= bytes else {
                overLimit = true
                return false
            }
            out.append(data)
        case .tail(let bytes):
            out.append(data)
            Self.keepTail(&out, bytes: bytes)
        }
        return true
    }

    func strings() -> (String, String) {
        lock.lock(); defer { lock.unlock() }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    /// Trims only when the buffer is twice the limit, so the copy is rare.
    private static func keepTail(_ data: inout Data, bytes: Int) {
        if data.count > bytes * 2 { data = Data(data.suffix(bytes)) }
    }
}
