import Foundation
import OMSCore

/// Transcribes all audio tracks of a session and writes TXT, SRT, VTT, JSON and MD files.
/// A session with parts transcribes each part that has no transcript yet, then joins the parts (ADR-0029).
enum TranscriptionService {
    static func engine(for settings: AppSettings) -> TranscriptionEngine {
        switch settings.asrMode {
        case .local: WhisperKitEngine.shared
        case .server: ServerAsrEngine(endpoint: settings.asrServerURL, model: settings.asrServerModel)
        }
    }

    /// `fraction` gets the done part of all tracks together (0…1).
    /// `allParts`: transcribe every part again. Otherwise only parts without a finished transcript.
    static func transcribe(_ session: SessionFolder, allParts: Bool = true, progress: @escaping @Sendable (String) -> Void,
                           fraction: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Transcript {
        let settings = AppSettings.current
        let engine = engine(for: settings)
        let metadata = try session.loadMetadata()
        let language = settings.speechLanguage == "auto" ? nil : settings.speechLanguage

        guard metadata.hasParts else {
            let (detected, tracks) = try await transcribeTracks(metadata.audioTracks, in: session.url, engine: engine,
                                                                language: language, done: 0, total: metadata.audioTracks.count,
                                                                partLabel: nil, progress: progress, fraction: fraction)
            let transcript = Transcript.merged(engine: engine.name, language: detected, tracks: tracks)
            try session.writeTranscript(transcript)
            return transcript
        }

        let todo = metadata.parts.filter { part in
            allParts || part.transcription != .done || !FileManager.default.fileExists(atPath: session.partTranscriptURL(part).path)
        }
        let total = todo.reduce(0) { $0 + $1.audioTracks.count }
        var done = 0
        for part in todo {
            try Task.checkCancellation()
            let number = part.number ?? 0
            let hasAudio = part.audioTracks.contains { FileManager.default.fileExists(atPath: session.partURL(part).appending(path: $0.file).path) }
            guard hasAudio else {
                // Media removed, but the part transcript exists: keep it.
                if FileManager.default.fileExists(atPath: session.partTranscriptURL(part).path) { continue }
                throw SessionPartsError.partNotReady(number)
            }
            let (detected, tracks) = try await transcribeTracks(part.audioTracks, in: session.partURL(part), engine: engine,
                                                                language: language, done: done, total: total,
                                                                partLabel: number, progress: progress, fraction: fraction)
            done += part.audioTracks.count
            let transcript = Transcript.merged(engine: engine.name, language: detected, tracks: tracks)
            try transcript.json().write(to: session.partTranscriptURL(part), options: .atomic)
            try session.updateMetadata { metadata in
                guard let index = metadata.parts.firstIndex(where: { $0.folder == part.folder }) else { return }
                metadata.parts[index].transcription = .done
                metadata.parts[index].transcriptionEngine = engine.name
            }
        }
        guard let combined = try session.combineTranscripts() else {
            throw SessionPartsError.partNotReady(metadata.parts.first { $0.transcription != .done }?.number ?? 0)
        }
        return combined
    }

    /// Transcribes the tracks of one recording. `done` and `total` count tracks over the whole job, for the progress.
    private static func transcribeTracks(
        _ audioTracks: [AudioTrackInfo], in folder: URL, engine: TranscriptionEngine, language: String?,
        done: Int, total: Int, partLabel: Int?, progress: @escaping @Sendable (String) -> Void,
        fraction: @escaping @Sendable (Double) -> Void
    ) async throws -> (String?, [(speaker: Speaker?, offset: Double, segments: [TranscriptSegment])]) {
        var tracks: [(speaker: Speaker?, offset: Double, segments: [TranscriptSegment])] = []
        var detected: String?
        let useSpeakers = audioTracks.count > 1
        let count = Double(max(total, 1))
        for (index, track) in audioTracks.enumerated() {
            try Task.checkCancellation()
            let url = folder.appending(path: track.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let label = track.speaker == .me ? String(localized: "microphone") : String(localized: "system audio")
            let position = done + index
            let result = try await engine.transcribe(url, language: language) { message in
                let text = String(localized: "Track \(position + 1)/\(max(total, 1)) (\(label)): \(message)")
                progress(partLabel.map { String(localized: "Part \($0)") + " · " + text } ?? text)
            } fraction: { value in
                fraction((Double(position) + min(1, max(0, value))) / count)
            }
            // An engine can return a partial result after a cancel. It must not become the transcript.
            try Task.checkCancellation()
            detected = detected ?? result.language
            tracks.append((useSpeakers ? track.speaker : nil, track.offset, result.segments))
        }
        return (detected, tracks)
    }

    static func hasTranscript(_ session: SessionFolder) -> Bool {
        FileManager.default.fileExists(atPath: session.transcriptURL("md").path)
    }
}
