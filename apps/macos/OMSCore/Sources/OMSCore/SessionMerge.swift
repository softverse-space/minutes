import Foundation

/// Merges a later session into an earlier session (ADR-0029).
///
/// The merge is a list of renames on one volume. The app writes `merge-journal.json` in the target before
/// the first move, so `recoverUnfinished` can complete a merge that a crash interrupted.
public enum SessionMerge {
    public static let journalName = "merge-journal.json"

    struct Journal: Codable {
        struct Move: Codable { var from: String; var to: String }
        /// Folder name of the source session, in the same parent folder as the target.
        var source: String
        /// `from` is relative to the parent folder, `to` relative to the target.
        var moves: [Move]
        var parts: [SessionPart]
        var outputs: [String]
    }

    /// Checks that `source` can merge into `target`. `target` must be the earlier session.
    public static func validate(target: SessionMetadata, source: SessionMetadata) throws {
        guard target.id != source.id else { throw SessionPartsError.sameSession }
        guard let targetEnd = target.endedAt, source.endedAt != nil else { throw SessionPartsError.notEnded }
        // One second of tolerance: the end time is written a moment after the last sample.
        guard source.startedAt.timeIntervalSince(targetEnd) > -1 else { throw SessionPartsError.overlap }
        let count = max(1, target.parts.count) + max(1, source.parts.count)
        guard count <= SessionFolder.maximumParts else { throw SessionPartsError.tooManyParts }
    }

    /// Break between the end of `target` and the start of `source`, in seconds.
    public static func gap(target: SessionMetadata, source: SessionMetadata) -> TimeInterval? {
        target.endedAt.map { max(0, source.startedAt.timeIntervalSince($0)) }
    }

    /// Merges `source` into `target`. Returns the combined transcript, or `nil` when a part still needs transcription.
    /// `trash` moves the empty source folder to the Trash. The caller holds both sessions (`SessionOperation.merge`).
    @discardableResult
    public static func merge(_ source: SessionFolder, into target: SessionFolder,
                             trash: (URL) throws -> Void) throws -> Transcript? {
        let sourceMetadata = try source.loadMetadata()
        try validate(target: try target.loadMetadata(), source: sourceMetadata)
        let targetMetadata = try target.convertToParts()

        var next = (targetMetadata.parts.compactMap(\.number).max() ?? 0) + 1
        var moves: [Journal.Move] = []
        var parts: [SessionPart] = []
        let sourceName = source.name

        if sourceMetadata.hasParts {
            for var part in sourceMetadata.parts {
                let folder = SessionFolder.partFolderName(next)
                moves.append(.init(from: "\(sourceName)/\(part.folder)", to: folder))
                part.folder = folder
                part.origin = .merged
                part.mergedFrom = sourceName
                parts.append(part)
                next += 1
            }
        } else {
            let folder = SessionFolder.partFolderName(next)
            let video = sourceMetadata.video ?? "recording.mov"
            moves.append(.init(from: "\(sourceName)/\(video)", to: "\(folder)/\(video)"))
            moves.append(.init(from: "\(sourceName)/audio", to: "\(folder)/audio"))
            moves.append(.init(from: "\(sourceName)/\(sourceName)_transcript.json", to: "\(folder)/transcript.json"))
            moves.append(.init(from: "\(sourceName)/frames", to: "\(folder)/frames"))
            var part = SessionPart(folder: folder, startedAt: sourceMetadata.startedAt, timeZone: sourceMetadata.timeZone, origin: .merged)
            part.mergedFrom = sourceName
            part.endedAt = sourceMetadata.endedAt
            part.video = sourceMetadata.video
            part.audioTracks = sourceMetadata.audioTracks
            part.sourceEvents = sourceMetadata.sourceEvents
            part.displayName = sourceMetadata.displayName
            part.microphoneName = sourceMetadata.microphoneName
            let hasTranscript = FileManager.default.fileExists(atPath: source.transcriptURL("json").path)
            part.transcription = hasTranscript && sourceMetadata.transcription == .done ? .done : .pending
            part.transcriptionEngine = sourceMetadata.transcriptionEngine
            part.interrupted = sourceMetadata.interrupted
            part.endReason = sourceMetadata.endReason
            parts.append(part)
        }

        // Summaries go to the outputs of the target. A name conflict gets `_v2`, `_v3` …
        var existing = Set(target.outputFiles().map(\.lastPathComponent))
        var outputs: [String] = []
        for file in source.outputFiles() {
            let name = SessionNaming.summaryFileName(date: sourceMetadata.startedAt, topic: "meeting", existing: existing,
                                                     proposedName: file.lastPathComponent)
            existing.insert(name)
            moves.append(.init(from: "\(sourceName)/outputs/\(file.lastPathComponent)", to: "outputs/\(name)"))
            outputs.append("outputs/\(name)")
        }

        let journal = Journal(source: sourceName, moves: moves, parts: parts, outputs: outputs)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: target.url.appending(path: journalName), options: .atomic)
        return try complete(journal, target: target, trash: trash)
    }

    /// Completes the merges that a crash interrupted. Call it at launch, before any other operation.
    /// Returns the targets whose merge failed again; their journal stays, and no file is deleted.
    @discardableResult
    public static func recoverUnfinished(in root: URL, trash: (URL) throws -> Void) -> [SessionFolder] {
        var failed: [SessionFolder] = []
        for session in SessionLibrary.list(in: root, limit: .max) {
            let url = session.url.appending(path: journalName)
            guard let data = try? Data(contentsOf: url) else { continue }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                try complete(try decoder.decode(Journal.self, from: data), target: session, trash: trash)
            } catch {
                failed.append(session)
            }
        }
        return failed
    }

    /// Does the moves that are not done yet, saves the parts and removes the source. Each step can run again.
    @discardableResult
    static func complete(_ journal: Journal, target: SessionFolder, trash: (URL) throws -> Void) throws -> Transcript? {
        let root = target.url.deletingLastPathComponent()
        for move in journal.moves {
            try SessionFolder.move(root.appending(path: move.from), to: target.url.appending(path: move.to))
        }
        let metadata = try target.updateMetadata { metadata in
            for part in journal.parts where !metadata.parts.contains(where: { $0.folder == part.folder }) {
                metadata.parts.append(part)
            }
            metadata.parts.sort { $0.startedAt < $1.startedAt }
            for output in journal.outputs where !metadata.outputs.contains(output) { metadata.outputs.append(output) }
            metadata.endedAt = metadata.parts.compactMap(\.endedAt).max() ?? metadata.endedAt
            metadata.interrupted = false
            metadata.endReason = nil
        }
        try target.writePartsMap(metadata)

        let source = root.appending(path: journal.source)
        if FileManager.default.fileExists(atPath: source.path) { try trash(source) }
        try FileManager.default.removeItem(at: target.url.appending(path: journalName))
        return try target.combineTranscripts()
    }
}
