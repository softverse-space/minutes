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

/// How a session came into the app (ADR-0034).
public enum SessionSource: String, Codable, Sendable {
    /// The app recorded the session.
    case recorded
    /// The user imported existing audio or video files.
    case imported
}

/// How a part came into its session (ADR-0029).
public enum PartOrigin: String, Codable, Sendable {
    case recorded, continued, merged
}

/// Why a recording ended (ADR-0030). `nil` in sessions recorded before this field existed.
public enum PartEndReason: String, Codable, Sendable {
    case stop, crash, quit, sleep, streamError, diskFull
}

/// One recording from Start (or Continue) to Stop inside a session with parts (ADR-0029).
/// File paths are relative to the part folder; source event times are relative to the part start.
public struct SessionPart: Codable, Sendable, Hashable {
    /// `parts/01`, `parts/02` …, relative to the session folder.
    public var folder: String
    public var startedAt: Date
    public var endedAt: Date?
    public var timeZone: String
    public var origin: PartOrigin
    /// Name of the session folder that a merge took this part from.
    public var mergedFrom: String?
    public var video: String?
    public var audioTracks: [AudioTrackInfo]
    public var sourceEvents: [SourceEvent]
    public var displayName: String?
    public var microphoneName: String?
    public var transcription: StepState
    public var transcriptionEngine: String?
    public var lastAliveAt: Date?
    public var interrupted: Bool
    public var endReason: PartEndReason?
    /// Name (without a path) of the file that the user imported as this part (ADR-0034).
    public var importedFileName: String?

    public init(folder: String, startedAt: Date, timeZone: String = TimeZone.current.identifier, origin: PartOrigin) {
        self.folder = folder
        self.startedAt = startedAt
        self.timeZone = timeZone
        self.origin = origin
        audioTracks = []
        sourceEvents = []
        transcription = .pending
        interrupted = false
    }

    enum CodingKeys: String, CodingKey {
        case folder, startedAt, endedAt, timeZone, origin, mergedFrom, video, audioTracks, sourceEvents,
             displayName, microphoneName, transcription, transcriptionEngine, lastAliveAt, interrupted, endReason,
             importedFileName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folder = try c.decode(String.self, forKey: .folder)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone) ?? TimeZone.current.identifier
        origin = try c.decodeIfPresent(PartOrigin.self, forKey: .origin) ?? .recorded
        mergedFrom = try c.decodeIfPresent(String.self, forKey: .mergedFrom)
        video = try c.decodeIfPresent(String.self, forKey: .video)
        audioTracks = try c.decodeIfPresent([AudioTrackInfo].self, forKey: .audioTracks) ?? []
        sourceEvents = try c.decodeIfPresent([SourceEvent].self, forKey: .sourceEvents) ?? []
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        microphoneName = try c.decodeIfPresent(String.self, forKey: .microphoneName)
        transcription = try c.decodeIfPresent(StepState.self, forKey: .transcription) ?? .pending
        transcriptionEngine = try c.decodeIfPresent(String.self, forKey: .transcriptionEngine)
        lastAliveAt = try c.decodeIfPresent(Date.self, forKey: .lastAliveAt)
        interrupted = try c.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
        endReason = try c.decodeIfPresent(PartEndReason.self, forKey: .endReason)
        importedFileName = try c.decodeIfPresent(String.self, forKey: .importedFileName)
    }

    /// Recorded time of the part, without breaks. `nil` while it records.
    public var duration: TimeInterval? {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt)) }
    }

    /// Part number from the folder name: `parts/02` → 2.
    public var number: Int? { Int(folder.split(separator: "/").last ?? "") }
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
    /// Parts of the session (ADR-0029). Empty: one recording in the layout of ADR-0006.
    public var parts: [SessionPart]
    /// Heartbeat of a running recording without parts (ADR-0030).
    public var lastAliveAt: Date?
    /// The recording (or the last part) ended without Stop.
    public var interrupted: Bool
    public var endReason: PartEndReason?
    /// `imported` for a session that the user made from existing files (ADR-0034).
    public var source: SessionSource
    /// Name (without a path) of the imported file of a session without parts.
    public var importedFileName: String?

    public init(id: UUID = UUID(), startedAt: Date, timeZone: TimeZone = .current) {
        self.id = id
        self.startedAt = startedAt
        self.timeZone = timeZone.identifier
        self.audioTracks = []
        self.sourceEvents = []
        self.transcription = .pending
        self.outputs = []
        self.parts = []
        self.interrupted = false
        self.source = .recorded
    }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, timeZone, displayName, microphoneName, video, audioTracks, sourceEvents,
             transcription, transcriptionEngine, transcriptionError, outputs, appVersion, mediaRemovedAt,
             parts, lastAliveAt, interrupted, endReason, source, importedFileName
    }

    /// Fields added after version 1.0.0 are optional, so old `session.json` files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        timeZone = try c.decode(String.self, forKey: .timeZone)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        microphoneName = try c.decodeIfPresent(String.self, forKey: .microphoneName)
        video = try c.decodeIfPresent(String.self, forKey: .video)
        audioTracks = try c.decode([AudioTrackInfo].self, forKey: .audioTracks)
        sourceEvents = try c.decode([SourceEvent].self, forKey: .sourceEvents)
        transcription = try c.decode(StepState.self, forKey: .transcription)
        transcriptionEngine = try c.decodeIfPresent(String.self, forKey: .transcriptionEngine)
        transcriptionError = try c.decodeIfPresent(String.self, forKey: .transcriptionError)
        outputs = try c.decode([String].self, forKey: .outputs)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        mediaRemovedAt = try c.decodeIfPresent(Date.self, forKey: .mediaRemovedAt)
        parts = try c.decodeIfPresent([SessionPart].self, forKey: .parts) ?? []
        lastAliveAt = try c.decodeIfPresent(Date.self, forKey: .lastAliveAt)
        interrupted = try c.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
        endReason = try c.decodeIfPresent(PartEndReason.self, forKey: .endReason)
        source = try c.decodeIfPresent(SessionSource.self, forKey: .source) ?? .recorded
        importedFileName = try c.decodeIfPresent(String.self, forKey: .importedFileName)
    }

    /// The user imported the session from existing files (ADR-0034).
    public var isImported: Bool { source == .imported }

    public var hasParts: Bool { !parts.isEmpty }

    /// Recorded time without breaks.
    public var duration: TimeInterval? {
        guard hasParts else { return endedAt.map { $0.timeIntervalSince(startedAt) } }
        let durations = parts.compactMap(\.duration)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }

    /// Time from the first start to the last end, with breaks.
    public var span: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    /// `true` when at least one recording of the session has an audio track.
    public var hasAudioTracks: Bool {
        hasParts ? parts.contains { !$0.audioTracks.isEmpty } : !audioTracks.isEmpty
    }

    /// The recording, or its last part, ended without Stop.
    public var isInterrupted: Bool { hasParts ? (parts.last?.interrupted ?? false) : interrupted }

    /// Offset of each part on the combined timeline: its start minus the start of the first part (ADR-0029).
    public func partOffset(_ part: SessionPart) -> TimeInterval {
        max(0, part.startedAt.timeIntervalSince(parts.first?.startedAt ?? startedAt))
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
    public static func summaryFileName(date: Date, topic: String, existing: Set<String>, proposedName: String? = nil) -> String {
        let proposed = proposedName.flatMap(validSummaryFileName)
        let base = proposed.map { String($0.dropLast(3)) } ?? "\(day(date))_meetingsummary_\(topic.isEmpty ? "meeting" : topic)"
        var name = "\(base).md"
        var version = 2
        while existing.contains(where: { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            name = "\(base)_v\(version).md"
            version += 1
        }
        return name
    }

    /// Reject paths, hidden files, control characters and names too long for version suffixes.
    public static func validSummaryFileName(_ name: String) -> String? {
        guard name.hasSuffix(".md"), name.count > 3, name.utf8.count <= 220,
              !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"),
              !name.contains(":"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return name
    }

    /// The version suffix of a summary file name: `…_llm_wiki_v2.md` → 2. Returns nil for the first version.
    public static func version(fromSummaryFileName fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        guard stem.contains("_meetingsummary_"),
              let range = stem.range(of: #"_v\d+$"#, options: .regularExpression) else { return nil }
        return Int(stem[range].dropFirst(2))
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
    /// The video of a session without parts. An imported session can have `recording.mp4` or `recording.mkv` (ADR-0034).
    public func videoURL(_ metadata: SessionMetadata) -> URL { url.appending(path: metadata.video ?? "recording.mov") }
    /// Video file names that the app writes. `frame-at.sh` reads the same names.
    public static let videoFileNames = ["recording.mov", "recording.mp4", "recording.mkv"]
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
            // A hidden folder is an import that has not finished (ADR-0034).
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map(SessionFolder.init(url:))
            .filter { FileManager.default.fileExists(atPath: $0.metadataURL.path) }
            .sorted { $0.name > $1.name }
            .prefix(limit)
            .map { $0 }
    }

    /// Deletes the video (`recording.mov`, `.mp4` or `.mkv`) in sessions older than `days`. Audio, transcripts and outputs stay.
    @discardableResult
    public static func removeOldVideos(in root: URL, olderThanDays days: Int, now: Date = Date()) -> [URL] {
        guard days > 0 else { return [] }
        var removed: [URL] = []
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        for session in list(in: root, limit: .max) {
            guard let metadata = try? session.loadMetadata(), metadata.startedAt < limit else { continue }
            // The root video of a session with one recording, and the video of each part (ADR-0029).
            let folders = [session.url] + session.partFoldersOnDisk
            let videos = folders.flatMap { folder in SessionFolder.videoFileNames.map { folder.appending(path: $0) } }
            for video in videos where FileManager.default.fileExists(atPath: video.path) {
                if (try? FileManager.default.removeItem(at: video)) != nil { removed.append(video) }
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
        // Parts: video, audio and old frames. The part transcript stays (ADR-0029).
        for part in partFoldersOnDisk {
            urls += [part.appending(path: "audio"), part.appending(path: "frames")]
            let partFiles = (try? fileManager.contentsOfDirectory(at: part, includingPropertiesForKeys: nil)) ?? []
            urls += partFiles.filter { Self.mediaExtensions.contains($0.pathExtension.lowercased()) }
        }
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
            let isMedia = Self.isMedia(relative: Array(relative), pathExtension: item.pathExtension.lowercased())
            if isMedia { media += bytes }
        }
        return (total, media)
    }

    private static let mediaExtensions: Set<String> = ["wav", "m4a", "mov", "mp4", "mkv"]

    /// `relative` is the path inside the session folder. Media: video and audio files in the root or in a part,
    /// and everything in `audio/` and `frames/` of the root or of a part.
    private static func isMedia(relative: [String], pathExtension: String) -> Bool {
        var path = relative[...]
        if path.count >= 3, path.first == "parts" { path = path.dropFirst(2) }
        if path.count == 1 { return mediaExtensions.contains(pathExtension) }
        return ["audio", "frames"].contains(path.first)
    }

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
        for part in partFoldersOnDisk {
            try FileManager.default.createDirectory(at: part.appending(path: "audio"), withIntermediateDirectories: true)
        }
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
