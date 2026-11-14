import AVFoundation
import CoreMedia
import ScreenCaptureKit
import Synchronization

enum RecorderError: LocalizedError {
    case displayNotFound
    case noVideoFrames
    case unsupportedAudioFormat
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .displayNotFound: String(localized: "The selected screen is not available. Select another screen.")
        case .noVideoFrames: String(localized: "The recording contains no video.")
        case .unsupportedAudioFormat: String(localized: "Unsupported audio format.")
        case .writerFailed(let message): String(localized: "Writing the recording failed: \(message)")
        }
    }
}

struct RecordingConfiguration {
    var displayID: CGDirectDisplayID
    var captureSystemAudio: Bool
    var captureMicrophone: Bool
    var microphoneID: String?
    var fps: Int
    var maxWidth: Int
    var videoURL: URL
    var systemAudioURL: URL
    var microphoneURL: URL
}

struct RecordingResult {
    /// `nil` when the video was not saved. `videoError` then gives the reason.
    var videoURL: URL?
    var videoError: Error?
    /// Audio files with offset (seconds) between video start and the first audio sample.
    var systemAudio: (url: URL, offset: Double)?
    var microphone: (url: URL, offset: Double)?
}

/// Records one display with system audio and microphone using ScreenCaptureKit.
/// Video goes to a .mov file (H.264, low frame rate). Each audio source goes to its own .m4a file.
///
/// Thread safety: writers and timestamps belong to `queue`. `start` sets them up before the stream
/// delivers any sample, and `stop` tears them down in one block on `queue`. Audio levels are published
/// through a `Mutex`, so the main actor never waits for the sample queue.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "sk.softverse.oms.recorder", qos: .userInitiated)
    private let meter = Mutex<(system: Float, microphone: Float)>((0, 0))
    /// Set on `queue` when `stop` begins. Late samples are dropped, because appending after
    /// `markAsFinished` raises an exception.
    private var isStopping = false
    /// Only the first write error is reported, although every following buffer fails too.
    private var didReportError = false
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemWriter: AudioTrackWriter?
    private var microphoneWriter: AudioTrackWriter?
    private var videoStartPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var configuration: RecordingConfiguration?

    /// Called once, on the sample queue or on ScreenCaptureKit's delegate queue, when recording fails.
    var onStreamError: (@Sendable (Error) -> Void)?

    func start(_ configuration: RecordingConfiguration) async throws {
        self.configuration = configuration
        let displays = try await SourceCatalog.shareableDisplays()
        guard let display = displays.first(where: { $0.displayID == configuration.displayID }) else {
            throw RecorderError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = Double(filter.pointPixelScale)
        var width = Int(Double(display.width) * scale)
        var height = Int(Double(display.height) * scale)
        if width > configuration.maxWidth {
            height = Int(Double(height) * Double(configuration.maxWidth) / Double(width))
            width = configuration.maxWidth
        }
        width -= width % 2
        height -= height % 2

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = width
        streamConfiguration.height = height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.fps))
        streamConfiguration.queueDepth = 6
        streamConfiguration.showsCursor = true
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.capturesAudio = configuration.captureSystemAudio
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2
        streamConfiguration.captureMicrophone = configuration.captureMicrophone
        if configuration.captureMicrophone, let microphoneID = configuration.microphoneID {
            streamConfiguration.microphoneCaptureDeviceID = microphoneID
        }

        try setUpWriter(url: configuration.videoURL, width: width, height: height, fps: configuration.fps)
        if configuration.captureSystemAudio { systemWriter = AudioTrackWriter(url: configuration.systemAudioURL) }
        if configuration.captureMicrophone { microphoneWriter = AudioTrackWriter(url: configuration.microphoneURL) }

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if configuration.captureSystemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if configuration.captureMicrophone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        try await stream.startCapture()
        self.stream = stream
    }

    /// Stops the capture and closes the files. A video error does not discard the audio:
    /// the result keeps the audio tracks, so the session can still be transcribed.
    func stop() async -> RecordingResult {
        if let stream { try? await stream.stopCapture() }
        stream = nil

        // One block on the sample queue, so no sample can arrive between the steps.
        let (writer, start, system, microphone) = queue.sync { () -> (AVAssetWriter?, CMTime?, AudioTrackWriter?, AudioTrackWriter?) in
            isStopping = true
            systemWriter?.close()
            microphoneWriter?.close()
            // A writer that failed or never started accepts no more calls; they raise an exception.
            if let writer, let videoInput, let start = videoStartPTS, writer.status == .writing {
                videoInput.markAsFinished()
                writer.endSession(atSourceTime: lastVideoPTS ?? start)
            }
            return (writer, videoStartPTS, systemWriter, microphoneWriter)
        }
        meter.withLock { $0 = (0, 0) }

        if let writer, writer.status == .writing { await writer.finishWriting() }
        var videoError: Error?
        if let writer, writer.status == .failed {
            videoError = RecorderError.writerFailed(writer.error?.localizedDescription ?? String(localized: "unknown error"))
        } else if writer?.status != .completed {
            videoError = RecorderError.noVideoFrames
        }

        func track(_ track: AudioTrackWriter?, _ url: URL?) -> (url: URL, offset: Double)? {
            guard let first = track?.firstPTS, let start, let url else { return nil }
            return (url, CMTimeGetSeconds(CMTimeSubtract(first, start)))
        }
        return RecordingResult(
            videoURL: videoError == nil ? configuration?.videoURL : nil,
            videoError: videoError,
            systemAudio: track(system, configuration?.systemAudioURL),
            microphone: track(microphone, configuration?.microphoneURL)
        )
    }

    // MARK: Live controls

    func setMuted(_ muted: Bool, microphone: Bool) {
        queue.async {
            if microphone { self.microphoneWriter?.isMuted = muted } else { self.systemWriter?.isMuted = muted }
        }
    }

    /// Current peak levels (0…1). Never blocks.
    func levels() -> (system: Float, microphone: Float) {
        meter.withLock { $0 }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, !isStopping else { return }
        switch type {
        case .screen: handleVideo(sampleBuffer)
        case .audio: append(sampleBuffer, to: systemWriter)
        case .microphone: append(sampleBuffer, to: microphoneWriter)
        @unknown default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.report(error) }
    }

    // MARK: Private

    private func setUpWriter(url: URL, width: Int, height: Int, fps: Int) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(1_000_000, width * height / 2),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 10,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.writerFailed("video input") }
        writer.add(input)
        self.writer = writer
        self.videoInput = input
        videoStartPTS = nil
        lastVideoPTS = nil
        isStopping = false
        didReportError = false
    }

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, let videoInput else { return }
        let pts = sampleBuffer.presentationTimeStamp
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return }

        guard status == .complete, sampleBuffer.imageBuffer != nil else {
            if videoStartPTS != nil, pts.isValid { lastVideoPTS = pts }
            return
        }

        if writer.status == .unknown {
            guard writer.startWriting() else { return reportWriterFailure(writer) }
            writer.startSession(atSourceTime: pts)
            videoStartPTS = pts
        }
        // The writer fails in the background, for example when the disk is full. The status shows it.
        guard writer.status == .writing else { return reportWriterFailure(writer) }
        if pts.isValid { lastVideoPTS = pts }
        if videoInput.isReadyForMoreMediaData, !videoInput.append(sampleBuffer) {
            reportWriterFailure(writer)
        }
    }

    private func reportWriterFailure(_ writer: AVAssetWriter) {
        report(RecorderError.writerFailed(writer.error?.localizedDescription ?? String(localized: "unknown error")))
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to track: AudioTrackWriter?) {
        // Audio before the first video frame has no place on the video timeline.
        guard let track, videoStartPTS != nil else { return }
        do {
            try track.append(sampleBuffer)
            meter.withLock { $0 = (systemWriter?.level ?? 0, microphoneWriter?.level ?? 0) }
        } catch {
            report(error)
        }
    }

    /// Runs on `queue`.
    private func report(_ error: Error) {
        guard !didReportError else { return }
        didReportError = true
        onStreamError?(error)
    }
}
