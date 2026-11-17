import Foundation

/// Transcript files of a session, and the combined transcript of a session with parts (ADR-0029).
public extension SessionFolder {
    static let transcriptExtensions = ["txt", "srt", "vtt", "md", "json"]

    /// Writes TXT, SRT, VTT, MD and JSON next to `session.json`.
    func writeTranscript(_ transcript: Transcript) throws {
        try transcript.plainText().write(to: transcriptURL("txt"), atomically: true, encoding: .utf8)
        try transcript.srt().write(to: transcriptURL("srt"), atomically: true, encoding: .utf8)
        try transcript.vtt().write(to: transcriptURL("vtt"), atomically: true, encoding: .utf8)
        try transcript.markdown().write(to: transcriptURL("md"), atomically: true, encoding: .utf8)
        try transcript.json().write(to: transcriptURL("json"), options: .atomic)
    }

    /// Removes the session transcript files. The part transcripts stay.
    func removeTranscriptFiles() {
        for ext in Self.transcriptExtensions { try? FileManager.default.removeItem(at: transcriptURL(ext)) }
    }

    func loadPartTranscript(_ part: SessionPart) -> Transcript? {
        guard let data = try? Data(contentsOf: partTranscriptURL(part)) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    /// `true` when each part has a finished part transcript.
    func allPartsTranscribed(_ metadata: SessionMetadata) -> Bool {
        metadata.parts.allSatisfy { $0.transcription == .done && FileManager.default.fileExists(atPath: partTranscriptURL($0).path) }
    }

    /// Joins the part transcripts into the session transcript and writes `parts.tsv`.
    ///
    /// Returns `nil` when a part has no finished transcript. The old session transcript is then removed,
    /// so nobody makes a summary from a transcript that misses a part.
    @discardableResult
    func combineTranscripts() throws -> Transcript? {
        let metadata = try loadMetadata()
        guard metadata.hasParts else { return nil }
        try writePartsMap(metadata)
        var pieces: [(part: TranscriptPart, transcript: Transcript)] = []
        var previousEnd: Double?
        for part in metadata.parts {
            guard part.transcription == .done, let transcript = loadPartTranscript(part) else {
                removeTranscriptFiles()
                _ = try updateMetadata { $0.transcription = .pending }
                return nil
            }
            let start = metadata.partOffset(part)
            let end = start + (part.duration ?? transcript.segments.map(\.end).max() ?? 0)
            let gap = previousEnd.map { max(0, start - $0) }
            pieces.append((TranscriptPart(number: part.number ?? pieces.count + 1, folder: part.folder, start: start, end: end,
                                          breakBefore: gap), transcript))
            previousEnd = end
        }
        let combined = Transcript.combined(parts: pieces)
        try writeTranscript(combined)
        _ = try updateMetadata {
            $0.transcription = .done
            $0.transcriptionError = nil
            $0.transcriptionEngine = combined.engine
        }
        return combined
    }
}
