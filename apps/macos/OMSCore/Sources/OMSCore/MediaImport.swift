import Foundation

/// Import of existing audio and video files as sessions (ADR-0034).
///
/// The app copies or converts each file into a hidden staging folder in the sessions folder.
/// When all files are ready, it writes `session.json` and renames the folder. The original files do not change.
public enum MediaImport {
    /// The audio track that the app makes from an imported file, relative to the recording folder.
    public static let audioFile = "audio/import.m4a"

    /// Files that AVFoundation reads without ffmpeg.
    public static let nativeExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aif", "aiff", "aifc", "caf", "flac", "aac", "mp4", "mov", "m4v",
    ]
    /// Files that only ffmpeg reads.
    public static let ffmpegExtensions: Set<String> = [
        "mkv", "mka", "webm", "ogg", "oga", "opus", "avi", "wma", "wmv", "flv", "3gp", "mpg", "mpeg", "ts", "mts",
    ]
    public static var supportedExtensions: Set<String> { nativeExtensions.union(ffmpegExtensions) }

    public static func isSupported(_ url: URL) -> Bool { supportedExtensions.contains(url.pathExtension.lowercased()) }
    public static func needsFfmpeg(_ url: URL) -> Bool { ffmpegExtensions.contains(url.pathExtension.lowercased()) }

    /// Name of the copied video in the session. `frame-at.sh` reads `mov`, `mp4` and `mkv`.
    /// The app copies `mov`, `mp4` and `m4v` as they are. ffmpeg puts the video of other containers into `mkv`.
    public static func videoFileName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov": "recording.mov"
        case "mp4", "m4v": "recording.mp4"
        default: "recording.mkv"
        }
    }

    // MARK: Folders

    static let stagingSuffix = ".importing"

    /// Name of a new session folder: the timestamp of the start, with `_2`, `_3` … when the name exists.
    public static func folderName(startedAt: Date, timeZone: TimeZone = .current, existing: Set<String>) -> String {
        let base = SessionNaming.timestamp(startedAt, timeZone: timeZone)
        var name = base
        var number = 2
        while existing.contains(name) || existing.contains(stagingName(for: name)) {
            name = "\(base)_\(number)"
            number += 1
        }
        return name
    }

    /// Hidden folder of an import that runs. `SessionLibrary.list` does not show it.
    public static func stagingName(for folderName: String) -> String { ".\(folderName)\(stagingSuffix)" }

    /// Names of the folders in `root`, also the hidden ones.
    public static func existingNames(in root: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
    }

    /// Removes the staging folders of imports that did not finish (a crash or a quit during the import).
    /// They hold only copies: the original files stay where they are.
    @discardableResult
    public static func removeUnfinished(in root: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names
            .filter { $0.hasPrefix(".") && $0.hasSuffix(stagingSuffix) }
            .map { root.appending(path: $0) }
            .filter { (try? FileManager.default.removeItem(at: $0)) != nil }
    }

    // MARK: Metadata

    /// One imported file after its conversion.
    public struct Item: Sendable, Equatable {
        /// Name of the original file, without its path.
        public var fileName: String
        public var startedAt: Date
        public var duration: TimeInterval
        /// File name of the copied video, or `nil` when the session keeps no video.
        public var video: String?

        public init(fileName: String, startedAt: Date, duration: TimeInterval, video: String?) {
            self.fileName = fileName
            self.startedAt = startedAt
            self.duration = duration
            self.video = video
        }
    }

    /// The one audio track of an imported file. With one track the transcript has no speakers,
    /// so the speaker value is not used.
    static var importedTrack: AudioTrackInfo { AudioTrackInfo(file: audioFile, speaker: .others, offset: 0) }

    /// Metadata of a session with one imported file, in the layout of ADR-0006.
    public static func metadata(for item: Item, timeZone: TimeZone = .current, appVersion: String? = nil) -> SessionMetadata {
        var metadata = SessionMetadata(startedAt: item.startedAt, timeZone: timeZone)
        metadata.endedAt = item.startedAt.addingTimeInterval(item.duration)
        metadata.source = .imported
        metadata.importedFileName = item.fileName
        metadata.video = item.video
        metadata.audioTracks = [importedTrack]
        metadata.appVersion = appVersion
        return metadata
    }

    /// Metadata of one session with each file as a part, in the layout of ADR-0029.
    /// The parts follow one another in the given order, without breaks. Part 1 starts at the start of the first item.
    public static func metadata(forParts items: [Item], timeZone: TimeZone = .current, appVersion: String? = nil) -> SessionMetadata {
        let start = items.first?.startedAt ?? Date()
        var metadata = SessionMetadata(startedAt: start, timeZone: timeZone)
        metadata.source = .imported
        metadata.appVersion = appVersion
        var partStart = start
        for (index, item) in items.enumerated() {
            var part = SessionPart(folder: SessionFolder.partFolderName(index + 1), startedAt: partStart,
                                   timeZone: timeZone.identifier, origin: .recorded)
            part.endedAt = partStart.addingTimeInterval(item.duration)
            part.video = item.video
            part.audioTracks = [importedTrack]
            part.importedFileName = item.fileName
            metadata.parts.append(part)
            partStart = part.endedAt ?? partStart
        }
        metadata.endedAt = partStart
        return metadata
    }

    /// Order of the files in one session: by file name, as Finder sorts them.
    public static func ordered(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
