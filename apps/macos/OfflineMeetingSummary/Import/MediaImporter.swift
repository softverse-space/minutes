import AVFoundation
import OMSCore

enum MediaImportError: LocalizedError {
    case unsupported([String])
    case ffmpegMissing(String)
    case noAudio(String)
    case conversionFailed(String, String)
    case insufficientDiskSpace
    case busy

    var errorDescription: String? {
        switch self {
        case .unsupported(let names):
            String(localized: "The app cannot import these files: \(names.joined(separator: ", ")).")
        case .ffmpegMissing(let name):
            String(localized: "To import \(name), install ffmpeg (brew install ffmpeg).")
        case .noAudio(let name):
            String(localized: "The file \(name) has no audio.")
        case .conversionFailed(let name, let message):
            String(localized: "Cannot convert \(name): \(message)")
        case .insufficientDiskSpace:
            String(localized: "The disk does not have enough free space for the import.")
        case .busy:
            String(localized: "Another import runs. Wait until it ends.")
        }
    }
}

/// Copies or converts one imported file into a session folder or a part folder (ADR-0034).
/// The original file does not change.
///
/// AVFoundation reads the common formats. ffmpeg reads the others, and the files that AVFoundation cannot open.
enum MediaImporter {
    struct Result: Sendable {
        var duration: TimeInterval
        /// File name of the copied video, or `nil`.
        var video: String?
    }

    static var ffmpeg: URL? { ProcessRunner.which("ffmpeg") }

    /// Formats that hold only audio. ffmpeg does not look for a video in them.
    private static let audioOnlyExtensions: Set<String> = ["mka", "ogg", "oga", "opus", "wma"]

    /// Start of the recording: the creation date in the media data, else the creation date of the file, else now.
    static func startDate(of url: URL) async -> Date {
        if !MediaImport.needsFfmpeg(url),
           let item = try? await AVURLAsset(url: url).load(.creationDate),
           let date = try? await item.load(.dateValue) {
            return date
        }
        return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
    }

    /// Writes `audio/import.m4a` into `folder` and, with `keepVideo`, a copy of the video.
    /// `progress` gets 0…1, or `nil` when the progress is not known (ffmpeg without ffprobe).
    static func importFile(_ url: URL, into folder: URL, keepVideo: Bool,
                           progress: @escaping @Sendable (Double?) -> Void) async throws -> Result {
        let name = url.lastPathComponent
        let audioURL = folder.appending(path: MediaImport.audioFile)
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var video: String?
        let native = MediaImport.needsFfmpeg(url) ? nil : await nativeTracks(url)
        if let native {
            guard native.hasAudio else { throw MediaImportError.noAudio(name) }
            try await exportAudio(url, to: audioURL, name: name, progress: progress)
            if keepVideo, native.hasVideo {
                let target = folder.appending(path: MediaImport.videoFileName(for: url))
                // On APFS the copy is a clone: fast and without extra space until a file changes.
                try FileManager.default.copyItem(at: url, to: target)
                video = target.lastPathComponent
            }
        } else {
            guard let ffmpeg else { throw MediaImportError.ffmpegMissing(name) }
            progress(nil)
            let total = await probeDuration(url)
            let copiesVideo = keepVideo && !audioOnlyExtensions.contains(url.pathExtension.lowercased())
            // The audio conversion takes most of the time. The video copy does not encode again.
            let audioShare = copiesVideo ? 0.8 : 1
            try await ffmpegAudio(ffmpeg, from: url, to: audioURL, name: name, duration: total) {
                progress($0 * audioShare)
            }
            if copiesVideo {
                video = try await ffmpegVideo(ffmpeg, from: url, into: folder, duration: total) {
                    progress(audioShare + $0 * (1 - audioShare))
                }
            }
        }

        let duration = (try? await AVURLAsset(url: audioURL).load(.duration).seconds) ?? 0
        guard duration.isFinite, duration > 0 else { throw MediaImportError.noAudio(name) }
        return Result(duration: duration, video: video)
    }

    /// The tracks that AVFoundation sees, or `nil` when it cannot read the file.
    private static func nativeTracks(_ url: URL) async -> (hasAudio: Bool, hasVideo: Bool)? {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isReadable)) == true,
              let audio = try? await asset.loadTracks(withMediaType: .audio),
              let video = try? await asset.loadTracks(withMediaType: .video) else { return nil }
        return (!audio.isEmpty, !video.isEmpty)
    }

    private static func exportAudio(_ url: URL, to target: URL, name: String,
                                     progress: @escaping @Sendable (Double?) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaImportError.conversionFailed(name, String(localized: "The audio export is not available."))
        }
        nonisolated(unsafe) let session = export
        let watcher = Task {
            for await state in session.states(updateInterval: 0.5) {
                if case .exporting(let exportProgress) = state { progress(exportProgress.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: target, as: .m4a)
        } catch {
            try Task.checkCancellation()
            throw MediaImportError.conversionFailed(name, error.localizedDescription)
        }
    }

    /// Duration of the file from ffprobe, or `nil` when ffprobe is missing or does not know it.
    private static func probeDuration(_ url: URL) async -> TimeInterval? {
        guard let ffprobe = ProcessRunner.which("ffprobe"),
              let result = try? await ProcessRunner.run(ffprobe, arguments: [
                  "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path,
              ], timeout: .seconds(30), stdout: .limited(bytes: 4096)),
              result.exitCode == 0,
              let seconds = Double(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
              seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    /// Runs ffmpeg with `-progress pipe:1` and sends the done part to `progress` when `duration` is known.
    private static func runFfmpeg(_ ffmpeg: URL, arguments: [String], duration: TimeInterval?,
                                  progress: @escaping @Sendable (Double) -> Void) async throws -> ProcessResult {
        var onStdout: (@Sendable (Data) -> Void)?
        if let duration {
            let parser = ProgressParser(MediaImport.FFmpegProgress(duration: duration))
            onStdout = { data in
                if let fraction = parser.consume(data) { progress(fraction) }
            }
        }
        let common = ["-nostdin", "-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1", "-y"]
        return try await ProcessRunner.run(ffmpeg, arguments: common + arguments,
                                           stdout: .tail(bytes: 64 * 1024), onStdout: onStdout)
    }

    /// Converts the first audio stream to AAC. A cancel stops ffmpeg (`ProcessRunner`).
    private static func ffmpegAudio(_ ffmpeg: URL, from url: URL, to target: URL, name: String, duration: TimeInterval?,
                                    progress: @escaping @Sendable (Double) -> Void) async throws {
        let result = try await runFfmpeg(ffmpeg, arguments: [
            "-i", url.path, "-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "128k", target.path,
        ], duration: duration, progress: progress)
        guard result.exitCode == 0 else {
            try? FileManager.default.removeItem(at: target)
            if result.stderr.contains("matches no streams") { throw MediaImportError.noAudio(name) }
            let message = result.stderr.split(separator: "\n").last.map(String.init) ?? "exit code \(result.exitCode)"
            throw MediaImportError.conversionFailed(name, message)
        }
    }

    /// Copies the first real video stream (not a cover picture) without a new encoding into `recording.mkv`.
    /// Returns `nil` when the file has no video or ffmpeg cannot copy it. The session then has only audio.
    private static func ffmpegVideo(_ ffmpeg: URL, from url: URL, into folder: URL, duration: TimeInterval?,
                                    progress: @escaping @Sendable (Double) -> Void) async throws -> String? {
        let target = folder.appending(path: "recording.mkv")
        let result = try await runFfmpeg(ffmpeg, arguments: [
            "-i", url.path, "-map", "0:V:0", "-c", "copy", "-an", "-sn", "-dn", target.path,
        ], duration: duration, progress: progress)
        guard result.exitCode == 0, FileStorage.size(of: target) > 0 else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return target.lastPathComponent
    }
}

/// Holds the parser state between the stdout chunks. ProcessRunner calls `consume` from its reader threads.
private final class ProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: MediaImport.FFmpegProgress

    init(_ parser: MediaImport.FFmpegProgress) { self.parser = parser }

    func consume(_ data: Data) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return parser.consume(String(decoding: data, as: UTF8.self))
    }
}
