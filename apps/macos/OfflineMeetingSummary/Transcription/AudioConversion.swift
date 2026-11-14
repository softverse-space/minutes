import AVFoundation

enum AudioConversionError: LocalizedError {
    case converterUnavailable
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .converterUnavailable: String(localized: "Cannot convert the audio to 16 kHz mono.")
        case .conversionFailed(let message): String(localized: "Audio conversion failed: \(message)")
        }
    }
}

enum AudioConversion {
    /// One finished WAV chunk. `count` is the expected number of chunks; rounding can add one more.
    struct Chunk {
        var url: URL
        /// Start of the chunk in the source, in seconds.
        var offset: Double
        var index: Int
        var count: Int
    }

    /// Converts an audio file to 16 kHz, mono, 16-bit PCM WAV chunks, one at a time.
    /// `handle` gets each chunk when it is complete. The chunk file is deleted when `handle` returns,
    /// so the disk holds one chunk and the caller gets the first result early.
    static func wav16kMonoChunks(from source: URL, into directory: URL, chunkSeconds: Double,
                                 handle: (Chunk) async throws -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = try AVAudioFile(forReading: source)
        let inputFormat = input.processingFormat
        let expectedCount = max(1, Int((Double(input.length) / inputFormat.sampleRate / chunkSeconds).rounded(.up)))
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioConversionError.converterUnavailable
        }

        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let framesPerChunk = AVAudioFramePosition(chunkSeconds * 16_000)
        let readCapacity: AVAudioFrameCount = 32_768
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: readCapacity),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 16_384) else {
            throw AudioConversionError.converterUnavailable
        }

        var current: AVAudioFile?
        var currentURL: URL?
        var chunkIndex = 0
        var chunkOffset = 0.0
        var framesInChunk: AVAudioFramePosition = 0
        var totalFrames: AVAudioFramePosition = 0
        var endOfInput = false
        // A read error must not look like the end of the file: the transcript would be cut without a message.
        var readError: Error?

        func openChunk() throws {
            let url = directory.appending(path: String(format: "chunk_%03d.wav", chunkIndex))
            current = try AVAudioFile(forWriting: url, settings: wavSettings, commonFormat: .pcmFormatInt16, interleaved: true)
            currentURL = url
            chunkOffset = Double(totalFrames) / 16_000
            framesInChunk = 0
        }

        func finishChunk() async throws {
            current?.close()
            current = nil
            guard let url = currentURL else { return }
            currentURL = nil
            defer { try? FileManager.default.removeItem(at: url) }
            if framesInChunk > 0 {
                try await handle(Chunk(url: url, offset: chunkOffset, index: chunkIndex, count: max(expectedCount, chunkIndex + 1)))
                chunkIndex += 1
            }
        }

        try openChunk()
        while true {
            // Conversion of a long recording takes minutes; Cancel must stop it.
            try Task.checkCancellation()
            var conversionError: NSError?
            outBuffer.frameLength = 0
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
                if endOfInput {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.read(into: readBuffer, frameCount: readCapacity)
                } catch {
                    readError = error
                    endOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if readBuffer.frameLength == 0 {
                    endOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return readBuffer
            }
            if let readError {
                throw AudioConversionError.conversionFailed(readError.localizedDescription)
            }
            if status == .error {
                throw AudioConversionError.conversionFailed(conversionError?.localizedDescription ?? String(localized: "unknown error"))
            }
            if outBuffer.frameLength > 0 {
                if framesInChunk >= framesPerChunk {
                    try await finishChunk()
                    try openChunk()
                }
                try current?.write(from: outBuffer)
                framesInChunk += AVAudioFramePosition(outBuffer.frameLength)
                totalFrames += AVAudioFramePosition(outBuffer.frameLength)
            }
            if status == .endOfStream || (status == .inputRanDry && endOfInput) { break }
        }
        try await finishChunk()
    }
}
