import Foundation

/// Folder layout and file moves of a session with parts (ADR-0029).
///
/// A session with one recording keeps the layout of ADR-0006. When it gets a second part,
/// `convertToParts()` moves the first recording to `parts/01/`.
public extension SessionFolder {
    static let maximumParts = 99

    var partsDirectory: URL { url.appending(path: "parts") }
    /// Map of the parts for the frame tool: `<offset>\t<duration>\t<NN>` per line.
    var partsMapURL: URL { url.appending(path: "parts.tsv") }

    /// `parts/01` for 1.
    static func partFolderName(_ number: Int) -> String {
        String(format: "parts/%02d", number)
    }

    func partURL(_ part: SessionPart) -> URL { url.appending(path: part.folder) }
    func partVideoURL(_ part: SessionPart) -> URL { partURL(part).appending(path: part.video ?? "recording.mov") }
    /// Transcript of one part. Times are relative to the start of the part.
    func partTranscriptURL(_ part: SessionPart) -> URL { partURL(part).appending(path: "transcript.json") }

    /// Part folders on disk (`parts/NN`), sorted. Used for storage, also when `session.json` is damaged.
    var partFoldersOnDisk: [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: partsDirectory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items
            .filter { $0.lastPathComponent.range(of: #"^\d{2}$"#, options: .regularExpression) != nil }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Moves the files of a session with one recording to `parts/01/` and saves the part in `session.json`.
    ///
    /// Idempotent: a move whose source is missing and whose target exists counts as done. So a crash
    /// between the moves and the save is repaired when the function runs again.
    /// The caller must hold the session (`SessionOperations`): no recording or transcription may run.
    @discardableResult
    func convertToParts() throws -> SessionMetadata {
        let metadata = try loadMetadata()
        guard !metadata.hasParts else { return metadata }

        let folderName = Self.partFolderName(1)
        let partURL = url.appending(path: folderName)
        try FileManager.default.createDirectory(at: partURL, withIntermediateDirectories: true)

        let videoName = metadata.video ?? "recording.mov"
        try Self.move(url.appending(path: videoName), to: partURL.appending(path: videoName))
        try Self.move(audioDirectory, to: partURL.appending(path: "audio"))
        let hadTranscript = FileManager.default.fileExists(atPath: transcriptURL("json").path)
            || FileManager.default.fileExists(atPath: partURL.appending(path: "transcript.json").path)
        try Self.move(transcriptURL("json"), to: partURL.appending(path: "transcript.json"))
        // The root keeps `audio/` as an empty folder, as in a new session.
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        return try updateMetadata { metadata in
            guard !metadata.hasParts else { return }
            var part = SessionPart(folder: folderName, startedAt: metadata.startedAt, timeZone: metadata.timeZone, origin: .recorded)
            part.endedAt = metadata.endedAt
            part.video = metadata.video
            part.audioTracks = metadata.audioTracks
            part.sourceEvents = metadata.sourceEvents
            part.displayName = metadata.displayName
            part.microphoneName = metadata.microphoneName
            part.transcription = hadTranscript && metadata.transcription == .done ? .done : .pending
            part.transcriptionEngine = metadata.transcriptionEngine
            part.lastAliveAt = metadata.lastAliveAt
            part.interrupted = metadata.interrupted
            part.endReason = metadata.endReason
            part.importedFileName = metadata.importedFileName
            metadata.parts = [part]
            metadata.video = nil
            metadata.audioTracks = []
            metadata.sourceEvents = []
            metadata.lastAliveAt = nil
            metadata.importedFileName = nil
        }
    }

    /// Writes `parts.tsv` for the frame tool. Only parts with a video and an end are in the map.
    /// The numbers always use a dot as the decimal separator.
    func writePartsMap(_ metadata: SessionMetadata) throws {
        guard metadata.hasParts else {
            try? FileManager.default.removeItem(at: partsMapURL)
            return
        }
        try Self.partsMap(metadata).write(to: partsMapURL, atomically: true, encoding: .utf8)
    }

    static func partsMap(_ metadata: SessionMetadata) -> String {
        metadata.parts.compactMap { part -> String? in
            guard part.video != nil, let duration = part.duration, let number = part.number else { return nil }
            return String(format: "%.3f\t%.3f\t%02d", locale: Locale(identifier: "en_US_POSIX"),
                          metadata.partOffset(part), duration, number)
        }.map { $0 + "\n" }.joined()
    }

    /// Moves `source` to `target`. Does nothing when the source is missing (an earlier run moved it).
    static func move(_ source: URL, to target: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) {
            // An empty folder that an earlier step created. A real conflict must not lose data.
            let contents = (try? fileManager.contentsOfDirectory(atPath: target.path)) ?? ["file"]
            guard contents.isEmpty else { throw SessionPartsError.targetExists(target.lastPathComponent) }
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: source, to: target)
    }
}

/// Errors of parts and merges. The app gives them a localized text, because OMSCore has no strings.
public enum SessionPartsError: Error, Equatable {
    /// A file with this name already exists in the target. Nothing was overwritten.
    case targetExists(String)
    case tooManyParts
    /// The part (number) has no audio and no transcript.
    case partNotReady(Int)
    /// The later session starts before the earlier session ends.
    case overlap
    /// A session has no end, because it still records.
    case notEnded
    case sameSession
}
