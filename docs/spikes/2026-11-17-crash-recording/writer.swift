// Crash spike writer. Usage: writer <mode> <outFile> <seconds> <crash|finish>
// Writes synthetic media in real time with the same APIs as the app, then either
// SIGKILLs itself (no cleanup, same as kill -9) or finishes normally.
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

let args = CommandLine.arguments
let mode = args[1]
let out = URL(fileURLWithPath: args[2])
let seconds = Double(args[3])!
let crash = args[4] == "crash"
try? FileManager.default.removeItem(at: out)

func log(_ s: String) { FileHandle.standardError.write("[\(mode)] \(s)\n".data(using: .utf8)!) }

let sampleRate = 48_000.0
let chunk = 4_800 // 100 ms
let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
var phase = 0.0

/// 440 Hz tone, with a 1 kHz beep in the first 100 ms of every 10 s (time marker).
func makeBuffer(index: Int, format: AVAudioFormat) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(Double(chunk) * format.sampleRate / sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let beep = index % 100 == 0
    let freq = beep ? 1000.0 : 440.0
    for i in 0..<Int(frames) {
        let v = Float(sin(phase) * 0.3)
        phase += 2 * .pi * freq / format.sampleRate
        if let f = buffer.floatChannelData {
            for c in 0..<Int(format.channelCount) { f[c][i] = v }
        } else if let s = buffer.int16ChannelData {
            s[0][i] = Int16(v * 32_000)
        }
    }
    return buffer
}

func sampleBuffer(_ buffer: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer {
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                                    presentationTimeStamp: pts, decodeTimeStamp: .invalid)
    var sb: CMSampleBuffer?
    CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
                         refcon: nil, formatDescription: buffer.format.formatDescription,
                         sampleCount: CMItemCount(buffer.frameLength), sampleTimingEntryCount: 1,
                         sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sb)
    let status = CMSampleBufferSetDataBufferFromAudioBufferList(sb!, blockBufferAllocator: kCFAllocatorDefault,
                                                                blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                flags: 0, bufferList: buffer.audioBufferList)
    precondition(status == noErr, "sample buffer \(status)")
    return sb!
}

func fragmentInterval(_ m: String) -> CMTime? {
    guard let r = m.range(of: "frag") else { return nil }
    return CMTime(seconds: Double(m[r.upperBound...])!, preferredTimescale: 600)
}

let start = Date()
func elapsed() -> Double { Date().timeIntervalSince(start) }
func pace(_ t: Double) { let d = t - elapsed(); if d > 0 { Thread.sleep(forTimeInterval: d) } }
func end() {
    if crash { log("SIGKILL at \(String(format: "%.1f", elapsed())) s"); kill(getpid(), SIGKILL) }
}

switch mode {
case let m where m.hasPrefix("video"):
    // Same settings as ScreenRecorder.setUpWriter: H.264, QuickTime, real time.
    let (w, h, fps) = (1280, 720, 10)
    let writer = try AVAssetWriter(outputURL: out, fileType: .mov)
    if let f = fragmentInterval(m) { writer.movieFragmentInterval = f }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h / 2, AVVideoExpectedSourceFrameRateKey: fps,
                                          AVVideoMaxKeyFrameIntervalKey: fps * 10]])
    input.expectsMediaDataInRealTime = true
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w,
        kCVPixelBufferHeightKey as String: h])
    writer.add(input)
    precondition(writer.startWriting(), "startWriting \(String(describing: writer.error))")
    writer.startSession(atSourceTime: .zero)
    var frame = 0
    while Double(frame) / Double(fps) < seconds {
        pace(Double(frame) / Double(fps))
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        // Brightness = second number, so a frame shows its own time.
        memset(CVPixelBufferGetBaseAddress(pb!), Int32((frame / fps * 7) % 256), CVPixelBufferGetDataSize(pb!))
        CVPixelBufferUnlockBaseAddress(pb!, [])
        if input.isReadyForMoreMediaData {
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        frame += 1
    }
    end()
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    log("finished \(writer.status.rawValue) \(String(describing: writer.error))")

case "audio-avfile-m4a", "audio-avfile-wav16k", "audio-avfile-caf16k":
    // AVAudioFile as AudioTrackWriter does today (m4a), or PCM 16 kHz mono 16-bit.
    let settings: [String: Any]
    let format: AVAudioFormat
    if mode == "audio-avfile-m4a" {
        settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        format = floatFormat
    } else {
        settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    }
    let file = try AVAudioFile(forWriting: out, settings: settings, commonFormat: format.commonFormat,
                               interleaved: format.isInterleaved)
    var i = 0
    while Double(i) * 0.1 < seconds {
        pace(Double(i) * 0.1)
        try file.write(from: makeBuffer(index: i, format: format))
        i += 1
    }
    end()
    file.close()
    log("closed")

case let m where m.hasPrefix("audio-writer"):
    // AVAssetWriter audio-only, AAC, QuickTime or MPEG-4 container, optional fragments.
    let type: AVFileType = m.contains("-mov") ? .mov : .m4a
    let writer = try AVAssetWriter(outputURL: out, fileType: type)
    if let f = fragmentInterval(m) { writer.movieFragmentInterval = f }
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000])
    input.expectsMediaDataInRealTime = true
    writer.add(input)
    precondition(writer.startWriting(), "startWriting \(String(describing: writer.error))")
    writer.startSession(atSourceTime: .zero)
    var i = 0, dropped = 0
    while Double(i) * 0.1 < seconds {
        pace(Double(i) * 0.1)
        let sb = sampleBuffer(makeBuffer(index: i, format: floatFormat),
                              pts: CMTime(value: CMTimeValue(i * chunk), timescale: CMTimeScale(sampleRate)))
        if input.isReadyForMoreMediaData { input.append(sb) } else { dropped += 1 }
        i += 1
    }
    if dropped > 0 { log("dropped \(dropped) buffers") }
    end()
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    log("finished \(writer.status.rawValue) \(String(describing: writer.error))")

default:
    fatalError("unknown mode \(mode)")
}
