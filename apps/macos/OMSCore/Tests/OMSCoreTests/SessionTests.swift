import Foundation
import Testing
@testable import OMSCore

struct SessionNamingTests {
    @Test func summaryNameAddsVersion() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = SessionNaming.summaryFileName(date: date, topic: "retro", existing: [])
        let second = SessionNaming.summaryFileName(date: date, topic: "retro", existing: [first])
        #expect(first.hasSuffix("_meetingsummary_retro.md"))
        #expect(second.hasSuffix("_meetingsummary_retro_v2.md"))
    }

    @Test(arguments: [
        ("2026-11-13_meetingsummary_client_onboarding.md", "client onboarding"),
        ("2026-11-13_meetingsummary_retro_v2.md", "retro"),
        ("2026-11-13_meetingsummary_meeting.md", nil),
        ("notes.md", nil),
    ] as [(String, String?)])
    func topicFromSummaryFileName(fileName: String, expected: String?) {
        #expect(SessionNaming.topic(fromSummaryFileName: fileName) == expected)
    }
}

struct SessionFolderTests {
    @Test func metadataRoundTripAndListing() throws {
        let root = try TemporaryDirectory()
        let folder = SessionFolder(url: root.url.appending(path: "2026-11-13_10-30-00"))
        try folder.createDirectories()
        var metadata = SessionMetadata(startedAt: Date(timeIntervalSince1970: 0))
        metadata.audioTracks = [AudioTrackInfo(file: "audio/mic.m4a", speaker: .me, offset: 0.2)]
        try folder.save(metadata)
        #expect(try folder.loadMetadata().audioTracks.first?.speaker == .me)
        #expect(SessionLibrary.list(in: root.url).map(\.name) == ["2026-11-13_10-30-00"])
        #expect(folder.transcriptURL("srt").lastPathComponent == "2026-11-13_10-30-00_transcript.srt")
    }

    @Test func updateKeepsChangesSavedByOthers() throws {
        let root = try TemporaryDirectory()
        let folder = SessionFolder(url: root.url.appending(path: "s"))
        try folder.createDirectories()
        try folder.save(SessionMetadata(startedAt: Date(timeIntervalSince1970: 0)))

        // A summary job adds an output while a transcription job is still running.
        try folder.updateMetadata { $0.outputs.append("outputs/a.md") }
        let updated = try folder.updateMetadata { $0.transcription = .done }

        #expect(updated.outputs == ["outputs/a.md"])
        #expect(try folder.loadMetadata().transcription == .done)
    }

    @Test func concurrentUpdatesAreNotLost() throws {
        let root = try TemporaryDirectory()
        let folder = SessionFolder(url: root.url.appending(path: "s"))
        try folder.createDirectories()
        try folder.save(SessionMetadata(startedAt: Date(timeIntervalSince1970: 0)))

        // Summary jobs add outputs while a transcription job changes its state, all on different threads.
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            _ = try? folder.updateMetadata {
                $0.outputs.append("outputs/\(index).md")
                if index.isMultiple(of: 10) { $0.transcription = .done }
            }
        }

        let metadata = try folder.loadMetadata()
        #expect(Set(metadata.outputs).count == 100)
        #expect(metadata.transcription == .done)
    }

    @Test func removesOldVideosOnly() throws {
        let root = try TemporaryDirectory()
        let folder = SessionFolder(url: root.url.appending(path: "old"))
        try folder.createDirectories()
        try folder.save(SessionMetadata(startedAt: Date(timeIntervalSince1970: 0)))
        try Data("v".utf8).write(to: folder.videoURL)
        try Data("t".utf8).write(to: folder.transcriptURL("txt"))
        let removed = SessionLibrary.removeOldVideos(in: root.url, olderThanDays: 30)
        #expect(removed.count == 1)
        #expect(FileManager.default.fileExists(atPath: folder.transcriptURL("txt").path))
    }

    @Test func retentionZeroKeepsEverything() throws {
        let root = try TemporaryDirectory()
        let folder = SessionFolder(url: root.url.appending(path: "old"))
        try folder.createDirectories()
        try folder.save(SessionMetadata(startedAt: Date(timeIntervalSince1970: 0)))
        try Data("v".utf8).write(to: folder.videoURL)
        #expect(SessionLibrary.removeOldVideos(in: root.url, olderThanDays: 0).isEmpty)
    }
}

struct StorageTests {
    let root: TemporaryDirectory
    let folder: SessionFolder

    init() throws {
        root = try TemporaryDirectory()
        folder = SessionFolder(url: root.url.appending(path: "2026-11-13_10-30-00"))
        try folder.createDirectories()
        try folder.save(SessionMetadata(startedAt: Date()))
        try Data(repeating: 1, count: 50_000).write(to: folder.videoURL)
        try Data(repeating: 2, count: 20_000).write(to: folder.audioDirectory.appending(path: "mic.m4a"))
        try Data(repeating: 3, count: 10_000).write(to: folder.url.appending(path: "2026-11-13_10-30-00_audio.wav"))
        try Data(repeating: 4, count: 5_000).write(to: folder.framesDirectory.appending(path: "at_00-01-00.jpg"))
        try "transcript".write(to: folder.transcriptURL("md"), atomically: true, encoding: .utf8)
        try "summary".write(to: folder.outputsDirectory.appending(path: "x.md"), atomically: true, encoding: .utf8)
    }

    @Test func removeSourceMediaKeepsTranscriptAndOutputs() throws {
        #expect(folder.hasSourceMedia)
        let freed = try folder.removeSourceMedia()
        #expect(freed >= 85_000)
        #expect(folder.hasSourceMedia == false)
        #expect(FileManager.default.fileExists(atPath: folder.videoURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: folder.transcriptURL("md").path))
        #expect(folder.outputFiles().count == 1)
        #expect(try folder.loadMetadata().mediaRemovedAt != nil)
    }

    @Test func onePassSizesMatchTheSeparateScans() throws {
        try Data(repeating: 5, count: 30_000).write(to: folder.outputsDirectory.appending(path: "clip.mov"))
        let sizes = folder.storageSizes()
        #expect(sizes.total == folder.size)
        #expect(sizes.media == folder.sourceMediaSize)
        // A media file in `outputs` is not source media.
        #expect(sizes.media < sizes.total)
        #expect(sizes.media >= 85_000)
    }

    @Test func moveToTrashRemovesFolder() throws {
        try folder.moveToTrash()
        #expect(FileManager.default.fileExists(atPath: folder.url.path) == false)
    }
}

struct SessionOperationsTests {
    let session = URL(filePath: "/sessions/a")
    let other = URL(filePath: "/sessions/b")

    @Test(arguments: SessionOperation.allCases, SessionOperation.allCases)
    func oneOperationForOneSession(running: SessionOperation, next: SessionOperation) {
        var operations = SessionOperations()
        let began1 = operations.begin(running, for: session)
        #expect(began1)
        let began2 = operations.begin(next, for: session)
        #expect(began2 == false)
        #expect(operations.isIdle(session) == false)
        operations.end(running, for: session)
        let began3 = operations.begin(next, for: session)
        #expect(began3)
    }

    @Test func sessionsDoNotBlockEachOther() {
        var operations = SessionOperations()
        let began4 = operations.begin(.cleanup, for: session)
        #expect(began4)
        let began5 = operations.begin(.transcription, for: other)
        #expect(began5)
        #expect(operations.operation(for: other) == .transcription)
    }

    @Test func endingAnotherOperationKeepsTheSessionBusy() {
        var operations = SessionOperations()
        let began6 = operations.begin(.summary, for: session)
        #expect(began6)
        operations.end(.cleanup, for: session)
        #expect(operations.isIdle(session) == false)
    }

    @Test func theSameFolderWithAnotherSpellingIsTheSameSession() {
        var operations = SessionOperations()
        let began7 = operations.begin(.recording, for: URL(filePath: "/sessions/x/../a/"))
        #expect(began7)
        let began8 = operations.begin(.cleanup, for: session)
        #expect(began8 == false)
    }
}
