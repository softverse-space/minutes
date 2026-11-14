import AVFoundation
import CoreMedia

/// Writes one audio source (microphone or system) to an AAC file.
/// Gaps between buffers are filled with silence, so the file keeps the real timeline.
/// All methods run on the recorder's sample queue.
final class AudioTrackWriter {
    let url: URL
    private var file: AVAudioFile?
    private var format: AVAudioFormat?
    private var nextPTS: CMTime?
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

        let format = try self.format ?? openFile(for: description)
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
        try file?.write(from: buffer)
        framesWritten += AVAudioFramePosition(frameCount)
    }

    func close() {
        file?.close()
        file = nil
    }

    private func openFile(for description: CMFormatDescription) throws -> AVAudioFormat {
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard format.commonFormat != .otherFormat else {
            throw RecorderError.unsupportedAudioFormat
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        self.format = format
        return format
    }

    private func writeSilence(seconds: Double, format: AVAudioFormat) throws {
        var remaining = AVAudioFrameCount(min(seconds, 3600) * format.sampleRate)
        while remaining > 0 {
            let chunk = min(remaining, 48_000)
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
            silence.frameLength = chunk
            zero(silence)
            try file?.write(from: silence)
            framesWritten += AVAudioFramePosition(chunk)
            remaining -= chunk
        }
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
