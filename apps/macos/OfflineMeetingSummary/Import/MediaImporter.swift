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
    /// `progress` gets 0…1, or `nil` when the progress is not known (ffmpeg).
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
            try await ffmpegAudio(ffmpeg, from: url, to: audioURL, name: name)
            if keepVideo, !audioOnlyExtensions.contains(url.pathExtension.lowercased()) {
                video = try await ffmpegVideo(ffmpeg, from: url, into: folder)
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

    /// Converts the first audio stream to AAC. A cancel stops ffmpeg (`ProcessRunner`).
    private static func ffmpegAudio(_ ffmpeg: URL, from url: URL, to target: URL, name: String) async throws {
        let result = try await ProcessRunner.run(ffmpeg, arguments: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", url.path, "-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "128k", target.path,
        ], stdout: .tail(bytes: 64 * 1024))
        guard result.exitCode == 0 else {
            try? FileManager.default.removeItem(at: target)
            if result.stderr.contains("matches no streams") { throw MediaImportError.noAudio(name) }
            let message = result.stderr.split(separator: "\n").last.map(String.init) ?? "exit code \(result.exitCode)"
            throw MediaImportError.conversionFailed(name, message)
        }
    }

    /// Copies the first real video stream (not a cover picture) without a new encoding into `recording.mkv`.
    /// Returns `nil` when the file has no video or ffmpeg cannot copy it. The session then has only audio.
    private static func ffmpegVideo(_ ffmpeg: URL, from url: URL, into folder: URL) async throws -> String? {
        let target = folder.appending(path: "recording.mkv")
        let result = try await ProcessRunner.run(ffmpeg, arguments: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", url.path, "-map", "0:V:0", "-c", "copy", "-an", "-sn", "-dn", target.path,
        ], stdout: .tail(bytes: 64 * 1024))
        guard result.exitCode == 0, FileStorage.size(of: target) > 0 else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return target.lastPathComponent
    }
}
