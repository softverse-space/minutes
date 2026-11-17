import Foundation

/// Who produced a segment. Derived from the audio track, not from voice recognition.
/// Raw values are stored in `session.json` and stay unchanged, so old sessions still load.
public enum Speaker: String, Codable, Sendable, CaseIterable {
    /// Microphone track: the person who records.
    case me = "ja"
    /// System audio track: the other participants.
    case others = "ostatní"

    /// Label in transcript files and in the prompt.
    public var label: String {
        switch self {
        case .me: "me"
        case .others: "others"
        }
    }
}

public struct TranscriptSegment: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var speaker: Speaker?
    public var text: String

    public init(start: Double, end: Double, speaker: Speaker? = nil, text: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.text = text
    }
}

/// Where one part starts and ends on the combined timeline (ADR-0029).
public struct TranscriptPart: Codable, Hashable, Sendable {
    public var number: Int
    public var folder: String
    public var start: Double
    public var end: Double
    /// Break before this part, in seconds. `nil` for the first part.
    public var breakBefore: Double?

    public init(number: Int, folder: String, start: Double, end: Double, breakBefore: Double?) {
        self.number = number
        self.folder = folder
        self.start = start
        self.end = end
        self.breakBefore = breakBefore
    }
}

public struct Transcript: Codable, Sendable {
    public var engine: String
    public var language: String?
    public var segments: [TranscriptSegment]
    /// Part boundaries of a session with parts. `nil` for a session with one recording.
    public var parts: [TranscriptPart]?

    public init(engine: String, language: String? = nil, segments: [TranscriptSegment], parts: [TranscriptPart]? = nil) {
        self.engine = engine
        self.language = language
        self.segments = segments
        self.parts = parts
    }

    /// Joins part transcripts on the combined timeline. Each part transcript has times relative to its part.
    public static func combined(parts: [(part: TranscriptPart, transcript: Transcript)]) -> Transcript {
        let sorted = parts.sorted { $0.part.start < $1.part.start }
        var engines: [String] = []
        for engine in sorted.map(\.transcript.engine) where !engines.contains(engine) { engines.append(engine) }
        var result = merged(
            engine: engines.joined(separator: ", "),
            language: sorted.lazy.compactMap(\.transcript.language).first,
            tracks: sorted.map { (speaker: nil, offset: $0.part.start, segments: $0.transcript.segments) }
        )
        result.parts = sorted.map(\.part)
        return result
    }

    /// Merges per-track segments into one timeline.
    /// - Parameter tracks: segments per speaker, with an offset (seconds) that aligns the track to the video timeline.
    public static func merged(
        engine: String,
        language: String?,
        tracks: [(speaker: Speaker?, offset: Double, segments: [TranscriptSegment])]
    ) -> Transcript {
        var all: [TranscriptSegment] = []
        for track in tracks {
            for segment in track.segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                all.append(TranscriptSegment(
                    start: max(0, segment.start + track.offset),
                    end: max(0, segment.end + track.offset),
                    speaker: track.speaker ?? segment.speaker,
                    text: text
                ))
            }
        }
        all.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        return Transcript(engine: engine, language: language, segments: all)
    }

    public var isEmpty: Bool { segments.isEmpty }

    public func plainText() -> String {
        segments.map(\.text).joined(separator: "\n") + "\n"
    }

    public func srt() -> String {
        segments.enumerated().map { index, segment in
            "\(index + 1)\n\(Timecode.format(segment.start, millisecondSeparator: ",")) --> \(Timecode.format(segment.end, millisecondSeparator: ","))\n\(label(segment))\(segment.text)\n"
        }.joined(separator: "\n")
    }

    public func vtt() -> String {
        "WEBVTT\n\n" + segments.map { segment in
            "\(Timecode.format(segment.start, millisecondSeparator: ".")) --> \(Timecode.format(segment.end, millisecondSeparator: "."))\n\(label(segment))\(segment.text)\n"
        }.joined(separator: "\n")
    }

    /// Readable transcript for the model: `[hh:mm:ss] ja: text`.
    /// A session with parts gets a marker line at the start of each part after the first.
    public func markdown() -> String {
        var markers = (parts ?? []).filter { $0.number > 1 || $0.breakBefore != nil }.sorted { $0.start < $1.start }[...]
        var lines: [String] = []
        for segment in segments {
            while let marker = markers.first, marker.start <= segment.start {
                lines.append(Self.markerLine(marker))
                markers = markers.dropFirst()
            }
            lines.append("[\(Timecode.format(segment.start))] \(label(segment))\(segment.text)")
        }
        lines += markers.map(Self.markerLine)
        return lines.joined(separator: "\n") + "\n"
    }

    /// `[00:33:10] --- Part 2. The recording continued after a break of 2 min 36 s. ---`
    static func markerLine(_ part: TranscriptPart) -> String {
        let gap = Int((part.breakBefore ?? 0).rounded())
        let pause = gap >= 60 ? "\(gap / 60) min \(gap % 60) s" : "\(gap) s"
        return "[\(Timecode.format(part.start))] --- Part \(part.number). The recording continued after a break of \(pause). ---"
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private func label(_ segment: TranscriptSegment) -> String {
        segment.speaker.map { "\($0.label): " } ?? ""
    }
}

/// Parses an OpenAI-compatible `verbose_json` transcription response.
public enum TranscriptionResponseParser {
    private struct Response: Decodable {
        struct Segment: Decodable { let start: Double; let end: Double; let text: String }
        let text: String?
        let language: String?
        let duration: Double?
        let segments: [Segment]?
    }

    public static func parse(_ data: Data) throws -> (language: String?, segments: [TranscriptSegment]) {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let segments = response.segments, !segments.isEmpty {
            return (response.language, segments.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text) })
        }
        let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return (response.language, []) }
        return (response.language, [TranscriptSegment(start: 0, end: response.duration ?? 0, text: text)])
    }
}
