import Foundation

public enum StepState: String, Codable, Sendable {
    case pending, running, done, failed
}

public struct SourceEvent: Codable, Sendable, Hashable {
    public var at: Double
    public var source: String
    public var enabled: Bool

    public init(at: Double, source: String, enabled: Bool) {
        self.at = at
        self.source = source
        self.enabled = enabled
    }
}

public struct AudioTrackInfo: Codable, Sendable, Hashable {
    /// File name relative to the session folder, e.g. `audio/mic.m4a`.
    public var file: String
    public var speaker: Speaker
    /// Seconds between video start and the first audio sample.
    public var offset: Double

    public init(file: String, speaker: Speaker, offset: Double) {
        self.file = file
        self.speaker = speaker
        self.offset = offset
    }
}

public struct SessionMetadata: Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var timeZone: String
    public var displayName: String?
    public var microphoneName: String?
    public var video: String?
    public var audioTracks: [AudioTrackInfo]
    public var sourceEvents: [SourceEvent]
    public var transcription: StepState
    public var transcriptionEngine: String?
    public var transcriptionError: String?
    public var outputs: [String]
    public var appVersion: String?
    /// When video and audio were removed to free space.
    public var mediaRemovedAt: Date?

    public init(id: UUID = UUID(), startedAt: Date, timeZone: TimeZone = .current) {
        self.id = id
        self.startedAt = startedAt
        self.timeZone = timeZone.identifier
        self.audioTracks = []
        self.sourceEvents = []
        self.transcription = .pending
        self.outputs = []
    }

    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

public enum SessionNaming {
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        String(timestamp(date, timeZone: timeZone).prefix(10))
    }

    /// `<date>_meetingsummary_<topic>.md`, with `_v2`, `_v3` … when the name exists.
    public static func summaryFileName(date: Date, topic: String, existing: Set<String>) -> String {
        let base = "\(day(date))_meetingsummary_\(topic.isEmpty ? "meeting" : topic)"
        var name = "\(base).md"
        var version = 2
        while existing.contains(name) {
            name = "\(base)_v\(version).md"
            version += 1
        }
        return name
    }

    /// Readable topic from a summary file name: `2026-11-13_meetingsummary_llm_wiki_v2.md` → `llm wiki`.
    /// Returns nil when the name does not follow `summaryFileName`.
    public static func topic(fromSummaryFileName fileName: String) -> String? {
        var stem = (fileName as NSString).deletingPathExtension
        guard let range = stem.range(of: "_meetingsummary_") else { return nil }
        stem = String(stem[range.upperBound...])
        if let version = stem.range(of: #"_v\d+$"#, options: .regularExpression) {
            stem.removeSubrange(version)
        }
        let topic = stem.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return topic.isEmpty || topic == "meeting" ? nil : topic
    }
}

/// File layout of one session folder (ADR-0006).
public struct SessionFolder: Sendable, Hashable, Identifiable {
    public let url: URL
    public var id: URL { url }

    public init(url: URL) { self.url = url }

    public var name: String { url.lastPathComponent }
    public var metadataURL: URL { url.appending(path: "session.json") }
    public var videoURL: URL { url.appending(path: "recording.mov") }
    public var audioDirectory: URL { url.appending(path: "audio") }
    public var framesDirectory: URL { url.appending(path: "frames") }
    public var outputsDirectory: URL { url.appending(path: "outputs") }

    public func transcriptURL(_ ext: String) -> URL {
        url.appending(path: "\(name)_transcript.\(ext)")
    }

    public func loadMetadata() throws -> SessionMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionMetadata.self, from: Data(contentsOf: metadataURL))
    }

    public func save(_ metadata: SessionMetadata) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    /// Serializes `updateMetadata` in this process. One lock for all sessions is enough: an update takes milliseconds.
    private static let metadataLock = NSLock()

    /// Reads the current `session.json`, applies `change` and saves it as one transaction.
    /// Use it instead of keeping a copy across an `await`: the copy would overwrite changes
    /// that another job (transcription, summary, mute events) saved in the meantime.
    /// Do not call `updateMetadata` inside `change`: the lock is not recursive.
    @discardableResult
    public func updateMetadata(_ change: (inout SessionMetadata) throws -> Void) throws -> SessionMetadata {
        Self.metadataLock.lock()
        defer { Self.metadataLock.unlock() }
        var metadata = try loadMetadata()
        try change(&metadata)
        try save(metadata)
        return metadata
    }

    public func createDirectories() throws {
        for directory in [url, audioDirectory, framesDirectory, outputsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func outputFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: outputsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

public enum SessionLibrary {
    /// Session folders in `root`, newest first. A folder is a session when it has `session.json`.
    public static func list(in root: URL, limit: Int = 20) -> [SessionFolder] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders
            .map(SessionFolder.init(url:))
            .filter { FileManager.default.fileExists(atPath: $0.metadataURL.path) }
            .sorted { $0.name > $1.name }
            .prefix(limit)
            .map { $0 }
    }

    /// Deletes `recording.mov` in sessions older than `days`. Audio, transcripts and outputs stay.
    @discardableResult
    public static func removeOldVideos(in root: URL, olderThanDays days: Int, now: Date = Date()) -> [URL] {
        guard days > 0 else { return [] }
        var removed: [URL] = []
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        for session in list(in: root, limit: .max) {
            guard let metadata = try? session.loadMetadata(), metadata.startedAt < limit,
                  FileManager.default.fileExists(atPath: session.videoURL.path) else { continue }
            if (try? FileManager.default.removeItem(at: session.videoURL)) != nil {
                removed.append(session.videoURL)
            }
        }
        return removed
    }
}

// MARK: - Storage management

public extension SessionFolder {
    /// Files that can be removed to free space: video, audio and frames.
    /// Transcripts, outputs and `session.json` stay.
    var sourceMediaURLs: [URL] {
        let fileManager = FileManager.default
        var urls = [videoURL, audioDirectory, framesDirectory]
        let files = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        urls += files.filter { Self.mediaExtensions.contains($0.pathExtension.lowercased()) }
        var seen = Set<String>()
        return urls.filter { fileManager.fileExists(atPath: $0.path) && seen.insert($0.standardizedFileURL.path).inserted }
    }

    var hasSourceMedia: Bool { sourceMediaURLs.contains { FileStorage.size(of: $0) > 0 } }

    var size: Int64 { FileStorage.size(of: url) }
    var sourceMediaSize: Int64 { sourceMediaURLs.reduce(0) { $0 + FileStorage.size(of: $1) } }

    /// `size` and `sourceMediaSize` from one pass over the folder.
    func storageSizes() -> (total: Int64, media: Int64) {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        let root = url.standardizedFileURL.pathComponents
        var total: Int64 = 0, media: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let item = enumerator?.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys), values.isDirectory != true else { continue }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            total += bytes
            let relative = item.standardizedFileURL.pathComponents.dropFirst(root.count)
            let isMedia = relative.count == 1
                ? Self.mediaExtensions.contains(item.pathExtension.lowercased())
                : ["audio", "frames"].contains(relative.first)
            if isMedia { media += bytes }
        }
        return (total, media)
    }

    private static let mediaExtensions: Set<String> = ["wav", "m4a", "mov", "mp4", "mkv"]

    /// Removes video, audio and frames. Returns freed bytes.
    @discardableResult
    func removeSourceMedia() throws -> Int64 {
        var freed: Int64 = 0
        for item in sourceMediaURLs {
            let size = FileStorage.size(of: item)
            try FileManager.default.removeItem(at: item)
            freed += size
        }
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try updateMetadata { $0.mediaRemovedAt = Date() }
        }
        return freed
    }

    /// Moves the whole session folder to the Trash.
    func moveToTrash() throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

public enum FileStorage {
    /// Allocated size of a file or a folder (recursive), in bytes.
    public static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let item = enumerator?.nextObject() as? URL {
            let itemValues = try? item.resourceValues(forKeys: keys)
            if itemValues?.isDirectory != true {
                total += Int64(itemValues?.totalFileAllocatedSize ?? itemValues?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
