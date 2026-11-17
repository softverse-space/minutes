import Foundation

/// Repairs sessions that a crash, a forced restart or a power loss left open (ADR-0030).
public enum SessionRecovery {
    /// Duration of a readable media file in seconds, or `nil` when the file is missing or not readable.
    /// The app checks the files with AVFoundation; tests give fixed values.
    public typealias MediaDuration = @Sendable (URL) async -> Double?

    /// Audio files that the recorder writes, and the speaker of each.
    static let knownTracks: [(file: String, speaker: Speaker)] = [("audio/system.m4a", .others), ("audio/mic.m4a", .me)]

    /// Repairs one session. Returns `true` when the session was interrupted (a recording without an end).
    /// The caller must not call it for the session that records now.
    @discardableResult
    public static func recover(_ session: SessionFolder, mediaDuration: MediaDuration) async throws -> Bool {
        var metadata = try session.loadMetadata()
        // A crash between the file moves and the save of a conversion to parts.
        if !metadata.hasParts, FileManager.default.fileExists(atPath: session.url.appending(path: SessionFolder.partFolderName(1)).path) {
            metadata = try session.convertToParts()
        }

        // Find the end of each recording without an end, outside the lock (AVFoundation is slow).
        var rootEnd: (end: Date, tracks: [AudioTrackInfo])?
        var partEnds: [String: (end: Date, tracks: [AudioTrackInfo])] = [:]
        if metadata.hasParts {
            for part in metadata.parts where part.endedAt == nil {
                partEnds[part.folder] = await estimate(base: session.partURL(part), startedAt: part.startedAt,
                                                       lastAliveAt: part.lastAliveAt, video: part.video,
                                                       tracks: part.audioTracks, mediaDuration: mediaDuration)
            }
        } else if metadata.endedAt == nil {
            rootEnd = await estimate(base: session.url, startedAt: metadata.startedAt, lastAliveAt: metadata.lastAliveAt,
                                     video: metadata.video, tracks: metadata.audioTracks, mediaDuration: mediaDuration)
        }

        var interrupted = false
        let updated = try session.updateMetadata { metadata in
            // A transcription that ran in an earlier app process does not run any more.
            if metadata.transcription == .running { metadata.transcription = .pending }
            for index in metadata.parts.indices where metadata.parts[index].transcription == .running {
                metadata.parts[index].transcription = .pending
            }
            if let rootEnd, metadata.endedAt == nil {
                metadata.endedAt = rootEnd.end
                metadata.audioTracks = rootEnd.tracks
                metadata.interrupted = true
                metadata.endReason = .crash
                interrupted = true
            }
            for index in metadata.parts.indices {
                guard metadata.parts[index].endedAt == nil, let end = partEnds[metadata.parts[index].folder] else { continue }
                metadata.parts[index].endedAt = end.end
                metadata.parts[index].audioTracks = end.tracks
                metadata.parts[index].interrupted = true
                metadata.parts[index].endReason = .crash
                metadata.endedAt = max(metadata.endedAt ?? end.end, end.end)
                interrupted = true
            }
        }
        if interrupted, updated.hasParts { try session.writePartsMap(updated) }
        return interrupted
    }

    /// End time from the longest readable media file, else from the heartbeat, else the start.
    /// Audio tracks: the known ones that are readable. Their offset from `session.json` stays.
    static func estimate(base: URL, startedAt: Date, lastAliveAt: Date?, video: String?, tracks: [AudioTrackInfo],
                         mediaDuration: MediaDuration) async -> (end: Date, tracks: [AudioTrackInfo]) {
        var durations: [Double] = []
        if let seconds = await mediaDuration(base.appending(path: video ?? "recording.mov")) { durations.append(seconds) }
        var readable: [AudioTrackInfo] = []
        let candidates = tracks.isEmpty
            ? knownTracks.map { AudioTrackInfo(file: $0.file, speaker: $0.speaker, offset: 0) }
            : tracks
        for track in candidates {
            if let seconds = await mediaDuration(base.appending(path: track.file)) {
                durations.append(seconds + track.offset)
                readable.append(track)
            }
        }
        if let longest = durations.max(), longest > 0 {
            return (startedAt.addingTimeInterval(longest), readable)
        }
        return (lastAliveAt ?? startedAt, readable)
    }
}
