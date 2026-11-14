import Foundation
import OMSCore

/// Transcribes all audio tracks of a session and writes TXT, SRT, VTT, JSON and MD files.
enum TranscriptionService {
    static func engine(for settings: AppSettings) -> TranscriptionEngine {
        switch settings.asrMode {
        case .local: WhisperKitEngine.shared
        case .server: ServerAsrEngine(endpoint: settings.asrServerURL, model: settings.asrServerModel)
        }
    }

    /// `fraction` gets the done part of all tracks together (0…1).
    static func transcribe(_ session: SessionFolder, progress: @escaping @Sendable (String) -> Void,
                           fraction: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Transcript {
        let settings = AppSettings.current
        let engine = engine(for: settings)
        let metadata = try session.loadMetadata()
        let language = settings.speechLanguage == "auto" ? nil : settings.speechLanguage

        var tracks: [(speaker: Speaker?, offset: Double, segments: [TranscriptSegment])] = []
        var detected: String?
        let useSpeakers = metadata.audioTracks.count > 1
        for (index, track) in metadata.audioTracks.enumerated() {
            try Task.checkCancellation()
            let url = session.url.appending(path: track.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let label = track.speaker == .me ? String(localized: "microphone") : String(localized: "system audio")
            let trackCount = Double(metadata.audioTracks.count)
            let result = try await engine.transcribe(url, language: language) { message in
                progress(String(localized: "Track \(index + 1)/\(metadata.audioTracks.count) (\(label)): \(message)"))
            } fraction: { value in
                fraction((Double(index) + min(1, max(0, value))) / trackCount)
            }
            detected = detected ?? result.language
            tracks.append((useSpeakers ? track.speaker : nil, track.offset, result.segments))
        }

        let transcript = Transcript.merged(engine: engine.name, language: detected, tracks: tracks)
        try write(transcript, to: session)
        return transcript
    }

    static func write(_ transcript: Transcript, to session: SessionFolder) throws {
        try transcript.plainText().write(to: session.transcriptURL("txt"), atomically: true, encoding: .utf8)
        try transcript.srt().write(to: session.transcriptURL("srt"), atomically: true, encoding: .utf8)
        try transcript.vtt().write(to: session.transcriptURL("vtt"), atomically: true, encoding: .utf8)
        try transcript.markdown().write(to: session.transcriptURL("md"), atomically: true, encoding: .utf8)
        try transcript.json().write(to: session.transcriptURL("json"), options: .atomic)
    }

    static func hasTranscript(_ session: SessionFolder) -> Bool {
        FileManager.default.fileExists(atPath: session.transcriptURL("md").path)
    }
}
