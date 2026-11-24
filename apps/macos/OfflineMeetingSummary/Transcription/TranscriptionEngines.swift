import Foundation
import OMSCore
import WhisperKit

protocol TranscriptionEngine: Sendable {
    var name: String { get }
    /// Transcribes one audio file. Segment times are relative to the start of the file.
    /// `progress` gets a status text, `fraction` the done part of this file (0…1).
    func transcribe(_ audio: URL, language: String?, progress: @escaping @Sendable (String) -> Void,
                    fraction: @escaping @Sendable (Double) -> Void) async throws -> (language: String?, segments: [TranscriptSegment])
}

enum TranscriptionError: LocalizedError {
    case modelMissing(String)
    case modelDamaged(String, String)
    case missingApiKey
    case badURL
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let model): String(localized: "Model \(model) is not downloaded. Download it in Settings → Transcription.")
        case .modelDamaged(let model, let detail): String(localized: "Model \(model) cannot load. Its files are incomplete or damaged. Download it again in Settings → Transcription. Details: \(detail)")
        case .missingApiKey: String(localized: "The API key for the transcription server is missing. Enter it in Settings → Transcription.")
        case .badURL: String(localized: "The transcription server URL is not valid.")
        case .server(let code, let body): String(localized: "The transcription server returned error \(code): \(String(body.prefix(300)))")
        }
    }
}

// MARK: - Local: WhisperKit

actor WhisperKitEngine: TranscriptionEngine {
    static let shared = WhisperKitEngine()

    nonisolated var name: String { "WhisperKit" }
    /// The loaded model, or the load in progress. Callers share one load instead of loading GBs twice.
    private var loading: (model: String, task: Task<LoadedModel, Error>)?

    /// WhisperKit is not `Sendable`. The engine is an actor and uses the instance only inside it,
    /// so passing it out of the load task in this box is safe.
    private final class LoadedModel: @unchecked Sendable {
        let kit: WhisperKit
        init(_ kit: WhisperKit) { self.kit = kit }
    }

    nonisolated static var downloadBase: URL { AppPaths.modelsDirectory }

    nonisolated static func modelFolder(_ model: String) -> URL {
        downloadBase.appending(path: "models/argmaxinc/whisperkit-coreml/\(model)")
    }

    /// The files that WhisperKit needs to load a model. An interrupted download can leave
    /// the `.mlmodelc` folders without some of these files.
    private nonisolated static let requiredFiles = ["MelSpectrogram", "AudioEncoder", "TextDecoder"].flatMap { name in
        ["coremldata.bin", "model.mil", "weights/weight.bin"].map { "\(name).mlmodelc/\($0)" }
    }

    nonisolated static func isDownloaded(_ model: String) -> Bool {
        let folder = modelFolder(model)
        return requiredFiles.allSatisfy { file in
            let size = (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: file).path)[.size]) as? Int
            return (size ?? 0) > 0
        }
    }

    /// Downloads the model from Hugging Face and loads it once (this also caches the tokenizer).
    /// The download starts from an empty folder, because the downloader skips files that it
    /// recorded as done, also when they are damaged.
    func download(_ model: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        if loading?.model == model { loading = nil }
        let folder = Self.modelFolder(model)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        let metadata = Self.downloadBase.appending(path: "models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/\(model)")
        try? FileManager.default.removeItem(at: metadata)
        _ = try await WhisperKit.download(variant: model, downloadBase: Self.downloadBase) { value in
            progress(value.fractionCompleted)
        }
        _ = try await kit(for: model)
    }

    func transcribe(_ audio: URL, language: String?, progress: @escaping @Sendable (String) -> Void,
                    fraction: @escaping @Sendable (Double) -> Void) async throws -> (language: String?, segments: [TranscriptSegment]) {
        let model = AppSettings.current.whisperModel
        guard Self.isDownloaded(model) else { throw TranscriptionError.modelMissing(model) }
        progress(String(localized: "Loading model…"))
        let kit: WhisperKit
        do {
            kit = try await self.kit(for: model)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionError.modelDamaged(model, error.localizedDescription)
        }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            chunkingStrategy: .vad
        )
        progress(String(localized: "Transcribing \(audio.lastPathComponent)…"))
        // WhisperKit reports progress only through its `Progress` object, so poll it.
        let kitProgress = kit.progress
        let poller = Task {
            while !Task.isCancelled {
                fraction(kitProgress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { poller.cancel() }
        let results = try await kit.transcribe(audioPath: audio.path, decodeOptions: options)
        // A cancel does not throw in WhisperKit: it returns the segments up to the cancel, often none.
        try Task.checkCancellation()
        fraction(1)
        let segments = results.flatMap(\.segments).map {
            TranscriptSegment(start: Double($0.start), end: Double($0.end), text: Self.clean($0.text))
        }
        return (results.first?.language, segments)
    }

    /// A load can take minutes (Core ML compiles the model). Cancel stops only the wait:
    /// the load continues and stays cached, so the next transcription does not start it again.
    private func kit(for model: String) async throws -> WhisperKit {
        if let loading, loading.model == model { return try await waitCancellably(for: loading.task).kit }
        let config = WhisperKitConfig(
            model: model,
            downloadBase: Self.downloadBase,
            modelFolder: Self.modelFolder(model).path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        let task = Task { LoadedModel(try await WhisperKit(config)) }
        loading = (model, task)
        do {
            return try await waitCancellably(for: task).kit
        } catch is CancellationError where !task.isCancelled {
            throw CancellationError()
        } catch {
            if loading?.model == model { loading = nil }
            throw error
        }
    }

    /// Removes leftover special tokens such as `<|0.00|>`.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Server: any OpenAI-compatible /audio/transcriptions API

struct ServerAsrEngine: TranscriptionEngine {
    var name: String { String(localized: "Transcription server (\(model))") }
    let endpoint: String
    let model: String
    /// Long audio is split, because servers limit the upload size.
    let chunkSeconds: Double = 600

    func transcribe(_ audio: URL, language: String?, progress: @escaping @Sendable (String) -> Void,
                    fraction: @escaping @Sendable (Double) -> Void) async throws -> (language: String?, segments: [TranscriptSegment]) {
        guard let key = Keychain.readAsrKey(), !key.isEmpty else { throw TranscriptionError.missingApiKey }
        guard let url = URL(string: endpoint) else { throw TranscriptionError.badURL }

        let work = FileManager.default.temporaryDirectory.appending(path: "oms-asr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        progress(String(localized: "Preparing audio…"))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 900
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var detected: String?
        var all: [TranscriptSegment] = []
        // Convert, send and delete one part at a time: the first result comes early and the disk holds one part.
        try await AudioConversion.wav16kMonoChunks(from: audio, into: work, chunkSeconds: chunkSeconds) { chunk in
            try Task.checkCancellation()
            progress(String(localized: "Sending part \(chunk.index + 1)/\(chunk.count) to the transcription server…"))
            fraction(Double(chunk.index) / Double(chunk.count))
            let (body, boundary) = try multipartFile(for: chunk.url, language: language)
            defer { try? FileManager.default.removeItem(at: body) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await session.upload(for: request, fromFile: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw TranscriptionError.server(status, String(decoding: data, as: UTF8.self))
            }
            let parsed = try TranscriptionResponseParser.parse(data)
            detected = detected ?? parsed.language
            all += parsed.segments.map {
                TranscriptSegment(start: $0.start + chunk.offset, end: $0.end + chunk.offset, text: $0.text)
            }
        }
        return (detected, all)
    }

    /// Writes the multipart body next to the audio part, so the upload streams from disk and not from memory.
    private func multipartFile(for file: URL, language: String?) throws -> (URL, String) {
        let boundary = "oms-\(UUID().uuidString)"
        var head = Data()
        func field(_ name: String, _ value: String) {
            head.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "verbose_json")
        field("timestamp_granularities[]", "segment")
        if let language { field("language", language) }
        head.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))

        let body = file.appendingPathExtension("multipart")
        try head.write(to: body)
        let output = try FileHandle(forWritingTo: body)
        defer { try? output.close() }
        try output.seekToEnd()
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let block = try input.read(upToCount: 1 << 20), !block.isEmpty {
            try output.write(contentsOf: block)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return (body, boundary)
    }
}
