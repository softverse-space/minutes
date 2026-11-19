import Foundation
import Testing
@testable import OMSCore

struct MediaImportTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func folderNameAddsANumberWhenTheNameExists() {
        let base = SessionNaming.timestamp(start, timeZone: .utc)
        #expect(MediaImport.folderName(startedAt: start, timeZone: .utc, existing: []) == base)
        #expect(MediaImport.folderName(startedAt: start, timeZone: .utc, existing: [base]) == "\(base)_2")
        #expect(MediaImport.folderName(startedAt: start, timeZone: .utc, existing: [base, "\(base)_2"]) == "\(base)_3")
        // A running import holds its name too.
        #expect(MediaImport.folderName(startedAt: start, timeZone: .utc,
                                       existing: [MediaImport.stagingName(for: base)]) == "\(base)_2")
    }

    @Test(arguments: [
        ("talk.MOV", "recording.mov"), ("talk.mp4", "recording.mp4"), ("talk.m4v", "recording.mp4"),
        ("talk.mkv", "recording.mkv"), ("talk.webm", "recording.mkv"), ("talk.avi", "recording.mkv"),
    ])
    func videoFileNameMatchesTheFrameTool(file: String, expected: String) {
        let name = MediaImport.videoFileName(for: URL(filePath: "/tmp/\(file)"))
        #expect(name == expected)
        #expect(SessionFolder.videoFileNames.contains(name))
    }

    @Test func supportedFiles() {
        #expect(MediaImport.isSupported(URL(filePath: "/a/b.MP3")))
        #expect(MediaImport.isSupported(URL(filePath: "/a/b.webm")))
        #expect(!MediaImport.isSupported(URL(filePath: "/a/b.txt")))
        #expect(MediaImport.needsFfmpeg(URL(filePath: "/a/b.mkv")))
        #expect(!MediaImport.needsFfmpeg(URL(filePath: "/a/b.m4a")))
    }

    @Test func orderFollowsFinder() {
        let urls = ["part 10.m4a", "part 2.m4a", "part 1.m4a"].map { URL(filePath: "/x/\($0)") }
        #expect(MediaImport.ordered(urls).map(\.lastPathComponent) == ["part 1.m4a", "part 2.m4a", "part 10.m4a"])
    }

    @Test func singleFileMetadata() {
        let item = MediaImport.Item(fileName: "call.mp3", startedAt: start, duration: 600, video: nil)
        let metadata = MediaImport.metadata(for: item, timeZone: .utc, appVersion: "1.3.0")
        #expect(metadata.isImported)
        #expect(!metadata.hasParts)
        #expect(metadata.endedAt == start.addingTimeInterval(600))
        #expect(metadata.audioTracks == [AudioTrackInfo(file: "audio/import.m4a", speaker: .others, offset: 0)])
        #expect(metadata.importedFileName == "call.mp3")
        #expect(metadata.transcription == .pending)
        #expect(metadata.duration == 600)
    }

    @Test func partsFollowOneAnotherWithoutBreaks() {
        let items = [
            MediaImport.Item(fileName: "a.mp4", startedAt: start, duration: 100, video: "recording.mp4"),
            MediaImport.Item(fileName: "b.m4a", startedAt: start.addingTimeInterval(-5000), duration: 50, video: nil),
        ]
        let metadata = MediaImport.metadata(forParts: items, timeZone: .utc)
        #expect(metadata.isImported)
        #expect(metadata.parts.map(\.folder) == ["parts/01", "parts/02"])
        #expect(metadata.parts.map { metadata.partOffset($0) } == [0, 100])
        #expect(metadata.parts.map(\.importedFileName) == ["a.mp4", "b.m4a"])
        #expect(metadata.endedAt == start.addingTimeInterval(150))
        #expect(metadata.duration == 150)
        // Only a part with a video is in the map of the frame tool.
        #expect(SessionFolder.partsMap(metadata) == "0.000\t100.000\t01\n")
    }

    @Test func importedFieldsSurviveSaveAndLoad() throws {
        let root = try TemporaryDirectory()
        let session = SessionFolder(url: root.url.appending(path: "s"))
        try session.createDirectories()
        let items = [MediaImport.Item(fileName: "a.m4a", startedAt: start, duration: 10, video: nil)]
        try session.save(MediaImport.metadata(forParts: items, timeZone: .utc))
        let loaded = try session.loadMetadata()
        #expect(loaded.source == .imported)
        #expect(loaded.parts.first?.importedFileName == "a.m4a")
    }

    @Test func oldSessionsAreRecorded() throws {
        let json = """
        {"audioTracks":[],"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","outputs":[],
         "sourceEvents":[],"startedAt":"2026-11-13T10:00:00Z","timeZone":"UTC","transcription":"done"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(SessionMetadata.self, from: Data(json.utf8))
        #expect(metadata.source == .recorded)
        #expect(metadata.importedFileName == nil)
    }

    @Test func listIgnoresUnfinishedImportsAndCleanupRemovesThem() throws {
        let root = try TemporaryDirectory()
        let staging = SessionFolder(url: root.url.appending(path: MediaImport.stagingName(for: "2026-01-01_10-00-00")))
        try staging.createDirectories()
        try staging.save(SessionMetadata(startedAt: start))
        let done = SessionFolder(url: root.url.appending(path: "2026-01-01_09-00-00"))
        try done.createDirectories()
        try done.save(SessionMetadata(startedAt: start))

        #expect(SessionLibrary.list(in: root.url).map(\.name) == [done.name])
        #expect(MediaImport.removeUnfinished(in: root.url).map(\.lastPathComponent) == [staging.name])
        #expect(!FileManager.default.fileExists(atPath: staging.url.path))
        #expect(FileManager.default.fileExists(atPath: done.url.path))
    }

    @Test func convertToPartsKeepsTheImportedFileName() throws {
        let root = try TemporaryDirectory()
        let session = SessionFolder(url: root.url.appending(path: "s"))
        try session.createDirectories()
        let item = MediaImport.Item(fileName: "talk.mp4", startedAt: start, duration: 60, video: "recording.mp4")
        try session.save(MediaImport.metadata(for: item, timeZone: .utc))
        try Data(repeating: 1, count: 10).write(to: session.url.appending(path: "recording.mp4"))
        try Data(repeating: 2, count: 10).write(to: session.url.appending(path: MediaImport.audioFile))

        let converted = try session.convertToParts()
        let part = try #require(converted.parts.first)
        #expect(part.importedFileName == "talk.mp4")
        #expect(converted.importedFileName == nil)
        #expect(FileManager.default.fileExists(atPath: session.partVideoURL(part).path))
        #expect(part.video == "recording.mp4")
    }

    @Test func oldVideoRemovalIncludesImportedVideos() throws {
        let root = try TemporaryDirectory()
        let session = SessionFolder(url: root.url.appending(path: "old"))
        try session.createDirectories()
        let item = MediaImport.Item(fileName: "talk.mp4", startedAt: Date(timeIntervalSinceNow: -40 * 86_400),
                                    duration: 60, video: "recording.mp4")
        try session.save(MediaImport.metadata(for: item))
        let video = session.url.appending(path: "recording.mp4")
        try Data(repeating: 1, count: 10).write(to: video)
        let audio = session.url.appending(path: MediaImport.audioFile)
        try Data(repeating: 2, count: 10).write(to: audio)

        let removed = SessionLibrary.removeOldVideos(in: root.url, olderThanDays: 30)
        #expect(removed.map(\.lastPathComponent) == ["recording.mp4"])
        #expect(!FileManager.default.fileExists(atPath: video.path))
        #expect(FileManager.default.fileExists(atPath: audio.path))
        #expect(session.videoURL(try session.loadMetadata()) == video)
    }
}
