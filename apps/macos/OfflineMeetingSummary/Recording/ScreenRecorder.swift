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
    /// `nil` in the audio-only mode: the recorder then uses the main display only for the capture filter.
    var displayID: CGDirectDisplayID?
    /// `false` records only audio. No video file is written (ADR-0032).
    var captureVideo: Bool
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
/// All files have movie fragments every 10 seconds, so they stay readable after a crash (ADR-0030).
///
/// In the audio-only mode (ADR-0032) the stream still needs a display, because ScreenCaptureKit captures
/// system audio only through a display filter. The recorder asks for very small frames and ignores them.
/// The timeline then starts at the first audio sample instead of the first video frame.
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
    /// Time zero of the recording: the first video frame, or in the audio-only mode the first audio sample.
    private var timelineStartPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var configuration: RecordingConfiguration?

    /// Called once, on the sample queue or on ScreenCaptureKit's delegate queue, when recording fails.
    var onStreamError: (@Sendable (Error) -> Void)?

    func start(_ configuration: RecordingConfiguration) async throws {
        self.configuration = configuration
        let displays = try await SourceCatalog.shareableDisplays()
        let display: SCDisplay
        if let displayID = configuration.displayID {
            guard let match = displays.first(where: { $0.displayID == displayID }) else { throw RecorderError.displayNotFound }
            display = match
        } else {
            guard let main = displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? displays.first else {
                throw RecorderError.displayNotFound
            }
            display = main
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = Double(filter.pointPixelScale)
        var width = Int(Double(display.width) * scale)
        var height = Int(Double(display.height) * scale)
        // Audio only: the frames are not used, so keep them as small as possible.
        let maxWidth = configuration.captureVideo ? configuration.maxWidth : 64
        if width > maxWidth {
            height = max(2, Int(Double(height) * Double(maxWidth) / Double(width)))
            width = maxWidth
        }
        width -= width % 2
        height -= height % 2

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = width
        streamConfiguration.height = height
        streamConfiguration.minimumFrameInterval = configuration.captureVideo
            ? CMTime(value: 1, timescale: CMTimeScale(configuration.fps))
            : CMTime(value: 1, timescale: 1)
        streamConfiguration.queueDepth = configuration.captureVideo ? 6 : 3
        streamConfiguration.showsCursor = configuration.captureVideo
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.capturesAudio = configuration.captureSystemAudio
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2
        streamConfiguration.captureMicrophone = configuration.captureMicrophone
        if configuration.captureMicrophone, let microphoneID = configuration.microphoneID {
            streamConfiguration.microphoneCaptureDeviceID = microphoneID
        }

        resetState()
        if configuration.captureVideo {
            try setUpWriter(url: configuration.videoURL, width: width, height: height, fps: configuration.fps)
        }
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
            systemWriter?.markAsFinished()
            microphoneWriter?.markAsFinished()
            // A writer that failed or never started accepts no more calls; they raise an exception.
            if let writer, let videoInput, let start = timelineStartPTS, writer.status == .writing {
                videoInput.markAsFinished()
                writer.endSession(atSourceTime: lastVideoPTS ?? start)
            }
            return (writer, timelineStartPTS, systemWriter, microphoneWriter)
        }
        meter.withLock { $0 = (0, 0) }

        if let writer, writer.status == .writing { await writer.finishWriting() }
        await system?.finish()
        await microphone?.finish()
        var videoError: Error?
        if configuration?.captureVideo == false {
            // Audio only: no video was planned, so a missing video is not an error.
        } else if let writer, writer.status == .failed {
            videoError = RecorderError.writerFailed(writer.error?.localizedDescription ?? String(localized: "unknown error"))
        } else if writer?.status != .completed {
            videoError = RecorderError.noVideoFrames
        }

        func track(_ track: AudioTrackWriter?, _ url: URL?) -> (url: URL, offset: Double)? {
            guard let first = track?.firstPTS, let start, let url else { return nil }
            return (url, CMTimeGetSeconds(CMTimeSubtract(first, start)))
        }
        return RecordingResult(
            videoURL: videoError == nil && configuration?.captureVideo == true ? configuration?.videoURL : nil,
            videoError: videoError,
            systemAudio: track(system, configuration?.systemAudioURL),
            microphone: track(microphone, configuration?.microphoneURL)
        )
    }

    // MARK: Live controls

    /// Offset (seconds) of each audio track from the video start, when its first sample arrived.
    /// The app saves it during the recording, so a recovered session has the right offsets.
    func trackOffsets() -> (system: Double?, microphone: Double?) {
        queue.sync {
            func offset(_ track: AudioTrackWriter?) -> Double? {
                guard let first = track?.firstPTS, let start = timelineStartPTS else { return nil }
                return CMTimeGetSeconds(CMTimeSubtract(first, start))
            }
            return (offset(systemWriter), offset(microphoneWriter))
        }
    }

    /// Writes the recorded data of all files to the disk with `F_FULLFSYNC`, off the sample queue.
    /// A power loss then loses at most the time since the last call (ADR-0030).
    func flushToDisk() {
        guard let configuration else { return }
        let urls = [configuration.videoURL, configuration.systemAudioURL, configuration.microphoneURL]
        DispatchQueue.global(qos: .utility).async {
            for url in urls {
                let descriptor = open(url.path, O_RDONLY)
                guard descriptor >= 0 else { continue }
                _ = fcntl(descriptor, F_FULLFSYNC)
                close(descriptor)
            }
        }
    }

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
        writer.movieFragmentInterval = AudioTrackWriter.fragmentInterval
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
    }

    private func resetState() {
        writer = nil
        videoInput = nil
        timelineStartPTS = nil
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
            if timelineStartPTS != nil, pts.isValid { lastVideoPTS = pts }
            return
        }

        if writer.status == .unknown {
            guard writer.startWriting() else { return reportWriterFailure(writer) }
            writer.startSession(atSourceTime: pts)
            timelineStartPTS = pts
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
        guard let track else { return }
        if configuration?.captureVideo == false, timelineStartPTS == nil {
            // Audio only: the first audio sample of any track starts the timeline.
            let pts = sampleBuffer.presentationTimeStamp
            guard pts.isValid else { return }
            timelineStartPTS = pts
        }
        // Audio before the first video frame has no place on the video timeline.
        guard timelineStartPTS != nil else { return }
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
