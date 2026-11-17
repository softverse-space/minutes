import AVFoundation
import CoreMedia

/// Writes one audio source (microphone or system) to an AAC `.m4a` file with movie fragments (ADR-0030).
/// A fragment every 10 seconds keeps the file readable after a crash; `AVAudioFile` reads it as before.
/// Gaps between buffers are filled with silence, so the file keeps the real timeline.
/// All methods except `finish()` run on the recorder's sample queue.
final class AudioTrackWriter {
    static let fragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

    let url: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var format: AVAudioFormat?
    private var nextPTS: CMTime?
    /// Position of the next sample in the file, in frames from `firstPTS`.
    private var timelineFrames: AVAudioFramePosition = 0
    /// Buffers that waited because the input was not ready. Appended in order, so the timeline stays.
    private var pending: [CMSampleBuffer] = []
    private(set) var firstPTS: CMTime?
    private(set) var framesWritten: AVAudioFramePosition = 0
    var isMuted = false
    /// Peak level 0…1 of the last buffer.
    private(set) var level: Float = 0

    init(url: URL) {
        self.url = url
    }

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard sampleBuffer.isValid, let description = sampleBuffer.formatDescription else { return }
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0 else { return }

        let format = try self.format ?? open(for: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: buffer.mutableAudioBufferList)
        guard status == noErr else { return }

        let pts = sampleBuffer.presentationTimeStamp
        if firstPTS == nil { firstPTS = pts }
        if let expected = nextPTS {
            let gap = CMTimeGetSeconds(CMTimeSubtract(pts, expected))
            if gap > 0.05 { try writeSilence(seconds: gap, format: format) }
        }
        nextPTS = CMTimeAdd(pts, CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(format.sampleRate)))

        if isMuted {
            zero(buffer)
            level = 0
        } else {
            level = peak(of: buffer)
        }
        try write(buffer)
    }

    /// Ends the input. Call it on the sample queue, so no sample can follow.
    func markAsFinished() {
        guard let writer, let input, writer.status == .writing else { return }
        flushPending()
        input.markAsFinished()
    }

    /// Closes the file. Call `markAsFinished()` first, on the sample queue.
    func finish() async {
        guard let writer, writer.status == .writing else { return }
        await writer.finishWriting()
    }

    // MARK: Private

    private func open(for description: CMFormatDescription) throws -> AVAudioFormat {
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard format.commonFormat != .otherFormat else {
            throw RecorderError.unsupportedAudioFormat
        }
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = Self.fragmentInterval
        let channels = Int(min(format.channelCount, 2))
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels > 1 ? 128_000 : 64_000,
        ], sourceFormatHint: format.formatDescription)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.writerFailed("audio input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "audio")
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.format = format
        return format
    }

    /// Appends PCM samples at the next position of the file timeline.
    private func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let writer, input != nil else { return }
        guard writer.status == .writing else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "audio")
        }
        let pts = CMTime(value: CMTimeValue(timelineFrames), timescale: CMTimeScale(buffer.format.sampleRate))
        let sample = try Self.sampleBuffer(buffer, at: pts)
        timelineFrames += AVAudioFramePosition(buffer.frameLength)
        framesWritten += AVAudioFramePosition(buffer.frameLength)
        pending.append(sample)
        flushPending()
        // A long stall of the encoder: keep at most about 30 s, then report the error.
        if pending.count > 300 { throw RecorderError.writerFailed("audio encoder is too slow") }
    }

    private func flushPending() {
        guard let input else { return }
        while let first = pending.first, input.isReadyForMoreMediaData {
            guard input.append(first) else { return }
            pending.removeFirst()
        }
    }

    private func writeSilence(seconds: Double, format: AVAudioFormat) throws {
        var remaining = AVAudioFrameCount(min(seconds, 3600) * format.sampleRate)
        while remaining > 0 {
            let chunk = min(remaining, 48_000)
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
            silence.frameLength = chunk
            zero(silence)
            try write(silence)
            remaining -= chunk
        }
    }

    /// A sample buffer with the PCM data of `buffer`. Each sample lasts 1 / sample rate (spike of ADR-0030).
    private static func sampleBuffer(_ buffer: AVAudioPCMBuffer, at pts: CMTime) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
                                        presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: buffer.format.formatDescription, sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw RecorderError.writerFailed("audio buffer \(status)") }
        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, bufferList: buffer.audioBufferList)
        guard status == noErr else { throw RecorderError.writerFailed("audio buffer \(status)") }
        return sample
    }

    private func zero(_ buffer: AVAudioPCMBuffer) {
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for audioBuffer in list {
            if let data = audioBuffer.mData { memset(data, 0, Int(audioBuffer.mDataByteSize)) }
        }
    }

    private func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        let stride = buffer.stride
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channels[channel]
            var index = 0
            while index < count * stride {
                peak = max(peak, abs(data[index]))
                index += stride * 8 // sample every 8th frame; enough for a meter
            }
        }
        return min(1, peak)
    }
}
