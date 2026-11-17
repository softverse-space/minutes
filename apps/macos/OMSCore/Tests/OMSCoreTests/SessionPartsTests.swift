import Foundation
import Testing
@testable import OMSCore

/// A session folder with one recording, as version 1.0.0 writes it.
private func makeSession(in root: URL, name: String, start: TimeInterval, length: TimeInterval,
                         transcript: [TranscriptSegment]? = nil, outputs: [String] = []) throws -> SessionFolder {
    let session = SessionFolder(url: root.appending(path: name))
    try session.createDirectories()
    var metadata = SessionMetadata(startedAt: Date(timeIntervalSince1970: start), timeZone: .utc)
    metadata.endedAt = Date(timeIntervalSince1970: start + length)
    metadata.video = "recording.mov"
    metadata.audioTracks = [AudioTrackInfo(file: "audio/mic.m4a", speaker: .me, offset: 0.1)]
    try Data(repeating: 1, count: 1000).write(to: session.videoURL)
    try Data(repeating: 2, count: 500).write(to: session.audioDirectory.appending(path: "mic.m4a"))
    if let transcript {
        try session.writeTranscript(Transcript(engine: "test", language: "sk", segments: transcript))
        metadata.transcription = .done
        metadata.transcriptionEngine = "test"
    }
    for output in outputs {
        try Data("# \(output)".utf8).write(to: session.outputsDirectory.appending(path: output))
        metadata.outputs.append("outputs/\(output)")
    }
    try session.save(metadata)
    return session
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

struct SessionMetadataCompatibilityTests {
    @Test func decodesASessionFromVersion1() throws {
        let json = """
        {"appVersion":"1.0.0","audioTracks":[{"file":"audio/mic.m4a","offset":0.2,"speaker":"ja"}],
         "endedAt":"2026-11-13T10:30:00Z","id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","outputs":[],
         "sourceEvents":[],"startedAt":"2026-11-13T10:00:00Z","timeZone":"Europe/Bratislava","transcription":"done"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(SessionMetadata.self, from: Data(json.utf8))
        #expect(metadata.parts.isEmpty)
        #expect(!metadata.interrupted)
        #expect(metadata.duration == 1800)
        #expect(metadata.hasAudioTracks)
    }

    @Test func durationWithPartsLeavesOutTheBreaks() {
        var metadata = SessionMetadata(startedAt: Date(timeIntervalSince1970: 0))
        var first = SessionPart(folder: "parts/01", startedAt: Date(timeIntervalSince1970: 0), origin: .recorded)
        first.endedAt = Date(timeIntervalSince1970: 600)
        var second = SessionPart(folder: "parts/02", startedAt: Date(timeIntervalSince1970: 900), origin: .continued)
        second.endedAt = Date(timeIntervalSince1970: 1200)
        metadata.parts = [first, second]
        metadata.endedAt = second.endedAt
        #expect(metadata.duration == 900)
        #expect(metadata.span == 1200)
        #expect(metadata.partOffset(second) == 900)
    }
}

struct SessionPartsTests {
    @Test func convertToPartsMovesTheRecordingAndIsIdempotent() throws {
        let root = try TemporaryDirectory()
        let session = try makeSession(in: root.url, name: "a", start: 0, length: 60,
                                      transcript: [TranscriptSegment(start: 1, end: 2, speaker: .me, text: "Ahoj")])
        try Data("jpg".utf8).write(to: session.framesDirectory.appending(path: "at_00-00-01.jpg"))

        let metadata = try session.convertToParts()
        let part = try #require(metadata.parts.first)
        #expect(metadata.parts.count == 1)
        #expect(part.folder == "parts/01")
        #expect(part.transcription == .done)
        #expect(part.audioTracks.first?.offset == 0.1)
        #expect(metadata.audioTracks.isEmpty && metadata.video == nil)
        #expect(exists(session.partVideoURL(part)))
        #expect(exists(session.partURL(part).appending(path: "audio/mic.m4a")))
        #expect(exists(session.partTranscriptURL(part)))
        #expect(!exists(session.videoURL))
        // Part 1 has offset 0, so the old frames stay valid in the root.
        #expect(exists(session.framesDirectory.appending(path: "at_00-00-01.jpg")))

        let again = try session.convertToParts()
        #expect(again.parts == metadata.parts)
    }

    @Test func convertToPartsRepairsAnInterruptedConversion() throws {
        let root = try TemporaryDirectory()
        let session = try makeSession(in: root.url, name: "a", start: 0, length: 60)
        // The files moved, but the app stopped before it saved `session.json`.
        let part = session.url.appending(path: "parts/01")
        try FileManager.default.createDirectory(at: part, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: session.videoURL, to: part.appending(path: "recording.mov"))

        let metadata = try session.convertToParts()
        #expect(metadata.parts.count == 1)
        #expect(exists(part.appending(path: "recording.mov")))
        #expect(exists(part.appending(path: "audio/mic.m4a")))
    }

    @Test func partsMapUsesADotAndSkipsPartsWithoutAnEnd() {
        var metadata = SessionMetadata(startedAt: Date(timeIntervalSince1970: 0))
        var first = SessionPart(folder: "parts/01", startedAt: Date(timeIntervalSince1970: 0), origin: .recorded)
        first.video = "recording.mov"
        first.endedAt = Date(timeIntervalSince1970: 1834.12)
        var second = SessionPart(folder: "parts/02", startedAt: Date(timeIntervalSince1970: 1990.5), origin: .continued)
        second.video = "recording.mov"
        metadata.parts = [first, second]
        #expect(SessionFolder.partsMap(metadata) == "0.000\t1834.120\t01\n")
        metadata.parts[1].endedAt = Date(timeIntervalSince1970: 2000.5)
        #expect(SessionFolder.partsMap(metadata) == "0.000\t1834.120\t01\n1990.500\t10.000\t02\n")
    }

    @Test func storageCountsAndRemovesTheMediaOfParts() throws {
        let root = try TemporaryDirectory()
        let session = try makeSession(in: root.url, name: "a", start: 0, length: 60,
                                      transcript: [TranscriptSegment(start: 1, end: 2, text: "x")])
        let metadata = try session.convertToParts()
        let part = try #require(metadata.parts.first)

        let paths = session.sourceMediaURLs.map(\.lastPathComponent)
        #expect(paths.contains("recording.mov"))
        #expect(paths.contains("audio"))
        let sizes = session.storageSizes()
        #expect(sizes.media > 0 && sizes.media < sizes.total)
        #expect(session.hasSourceMedia)

        try session.removeSourceMedia()
        #expect(!exists(session.partVideoURL(part)))
        #expect(exists(session.partURL(part).appending(path: "audio")))
        #expect(exists(session.partTranscriptURL(part)))
        #expect(!session.hasSourceMedia)
    }

    @Test func oldVideosOfPartsAreRemoved() throws {
        let root = try TemporaryDirectory()
        let session = try makeSession(in: root.url, name: "a", start: 0, length: 60)
        let part = try #require(try session.convertToParts().parts.first)
        let removed = SessionLibrary.removeOldVideos(in: root.url, olderThanDays: 1, now: Date(timeIntervalSince1970: 10 * 86_400))
        #expect(removed.count == 1)
        #expect(!exists(session.partVideoURL(part)))
        #expect(exists(session.partURL(part).appending(path: "audio/mic.m4a")))
    }
}

struct CombinedTranscriptTests {
    @Test func partsMoveToTheCombinedTimelineWithMarkerLines() {
        let first = Transcript(engine: "w", language: "sk", segments: [TranscriptSegment(start: 5, end: 8, speaker: .me, text: "Prvá")])
        let second = Transcript(engine: "w", segments: [TranscriptSegment(start: 2, end: 4, speaker: .others, text: "Druhá")])
        let combined = Transcript.combined(parts: [
            (TranscriptPart(number: 2, folder: "parts/02", start: 1990, end: 2600, breakBefore: 156), second),
            (TranscriptPart(number: 1, folder: "parts/01", start: 0, end: 1834, breakBefore: nil), first),
        ])
        #expect(combined.segments.map(\.start) == [5, 1992])
        #expect(combined.language == "sk")
        #expect(combined.engine == "w")
        #expect(combined.markdown() == """
        [00:00:05] me: Prvá
        [00:33:10] --- Part 2. The recording continued after a break of 2 min 36 s. ---
        [00:33:12] others: Druhá

        """)
        // SRT, VTT and TXT get no marker lines.
        #expect(!combined.srt().contains("---"))
    }

    @Test func aPartWithoutSpeechStillGetsItsMarker() {
        let combined = Transcript.combined(parts: [
            (TranscriptPart(number: 1, folder: "parts/01", start: 0, end: 10, breakBefore: nil),
             Transcript(engine: "w", segments: [TranscriptSegment(start: 1, end: 2, text: "a")])),
            (TranscriptPart(number: 2, folder: "parts/02", start: 70, end: 80, breakBefore: 60), Transcript(engine: "w", segments: [])),
        ])
        #expect(combined.markdown().hasSuffix("[00:01:10] --- Part 2. The recording continued after a break of 1 min 0 s. ---\n"))
    }

    @Test func combineNeedsATranscriptOfEachPart() throws {
        let root = try TemporaryDirectory()
        let session = try makeSession(in: root.url, name: "a", start: 0, length: 60,
                                      transcript: [TranscriptSegment(start: 1, end: 2, text: "x")])
        try session.convertToParts()
        try session.updateMetadata {
            var part = SessionPart(folder: "parts/02", startedAt: Date(timeIntervalSince1970: 100), origin: .continued)
            part.endedAt = Date(timeIntervalSince1970: 160)
            part.video = "recording.mov"
            $0.parts.append(part)
        }
        #expect(try session.combineTranscripts() == nil)
        #expect(!exists(session.transcriptURL("md")))
        #expect(try session.loadMetadata().transcription == .pending)
        #expect(exists(session.partsMapURL))

        try FileManager.default.createDirectory(at: session.url.appending(path: "parts/02"), withIntermediateDirectories: true)
        try Transcript(engine: "w", segments: [TranscriptSegment(start: 3, end: 4, text: "y")]).json()
            .write(to: session.url.appending(path: "parts/02/transcript.json"))
        try session.updateMetadata { $0.parts[1].transcription = .done }
        let combined = try #require(try session.combineTranscripts())
        #expect(combined.segments.map(\.start) == [1, 103])
        #expect(combined.parts?.last?.breakBefore == 40)
        #expect(try String(contentsOf: session.transcriptURL("md"), encoding: .utf8).contains("--- Part 2."))
        #expect(try session.loadMetadata().transcription == .done)
    }

    @Test func promptMentionsTheParts() {
        let request = SummaryRequest(template: nil, customInstruction: "x", detail: .brief, language: "sk",
                                     meetingDate: Date(timeIntervalSince1970: 0), frameToolPath: nil, partCount: 2)
        let prompt = PromptBuilder.build(request, details: DetailLevelCatalog(instructions: [:]))
        #expect(prompt.contains("The recording has 2 parts."))
        let single = SummaryRequest(template: nil, customInstruction: "x", detail: .brief, language: "sk",
                                    meetingDate: Date(timeIntervalSince1970: 0), frameToolPath: nil)
        #expect(!PromptBuilder.build(single, details: DetailLevelCatalog(instructions: [:])).contains("parts."))
    }
}

struct SessionMergeTests {
    private func trash(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    @Test func mergesTwoTranscribedSessionsWithoutANewTranscription() throws {
        let root = try TemporaryDirectory()
        let target = try makeSession(in: root.url, name: "a", start: 0, length: 600,
                                     transcript: [TranscriptSegment(start: 10, end: 12, speaker: .me, text: "Prvá")],
                                     outputs: ["1970-01-01_meetingsummary_retro.md"])
        let source = try makeSession(in: root.url, name: "b", start: 700, length: 300,
                                     transcript: [TranscriptSegment(start: 5, end: 6, speaker: .others, text: "Druhá")],
                                     outputs: ["1970-01-01_meetingsummary_retro.md"])
        try Data("jpg".utf8).write(to: source.framesDirectory.appending(path: "at_00-00-05.jpg"))

        let combined = try #require(try SessionMerge.merge(source, into: target, trash: trash))
        #expect(combined.segments.map(\.start) == [10, 705])
        #expect(!exists(source.url))
        #expect(!exists(target.url.appending(path: SessionMerge.journalName)))

        let metadata = try target.loadMetadata()
        #expect(metadata.parts.map(\.folder) == ["parts/01", "parts/02"])
        #expect(metadata.parts[1].origin == .merged)
        #expect(metadata.parts[1].mergedFrom == "b")
        #expect(metadata.endedAt == Date(timeIntervalSince1970: 1000))
        #expect(metadata.transcription == .done)
        #expect(Set(target.outputFiles().map(\.lastPathComponent))
                == ["1970-01-01_meetingsummary_retro.md", "1970-01-01_meetingsummary_retro_v2.md"])
        #expect(metadata.outputs.contains("outputs/1970-01-01_meetingsummary_retro_v2.md"))
        #expect(exists(target.url.appending(path: "parts/02/recording.mov")))
        #expect(exists(target.url.appending(path: "parts/02/frames/at_00-00-05.jpg")))
        #expect(try String(contentsOf: target.partsMapURL, encoding: .utf8) == "0.000\t600.000\t01\n700.000\t300.000\t02\n")
    }

    @Test func aSessionWithPartsMergesAllItsParts() throws {
        let root = try TemporaryDirectory()
        let target = try makeSession(in: root.url, name: "a", start: 0, length: 100)
        let source = try makeSession(in: root.url, name: "b", start: 200, length: 100)
        let third = try makeSession(in: root.url, name: "c", start: 400, length: 100)
        try SessionMerge.merge(third, into: source, trash: trash)
        let result = try SessionMerge.merge(source, into: target, trash: trash)

        #expect(result == nil) // No part has a transcript.
        let metadata = try target.loadMetadata()
        #expect(metadata.parts.map(\.folder) == ["parts/01", "parts/02", "parts/03"])
        #expect(metadata.parts.map(\.mergedFrom) == [nil, "b", "b"])
        #expect(exists(target.url.appending(path: "parts/03/recording.mov")))
        #expect(metadata.transcription == .pending)
    }

    @Test func overlappingSessionsDoNotMerge() throws {
        let root = try TemporaryDirectory()
        let target = try makeSession(in: root.url, name: "a", start: 0, length: 600)
        let source = try makeSession(in: root.url, name: "b", start: 500, length: 300)
        #expect(throws: SessionPartsError.overlap) { try SessionMerge.merge(source, into: target, trash: trash) }
        #expect(exists(source.videoURL))
        #expect(try target.loadMetadata().parts.isEmpty)
    }

    @Test func aMergeThatStoppedIsCompletedAtTheNextLaunch() throws {
        let root = try TemporaryDirectory()
        let target = try makeSession(in: root.url, name: "a", start: 0, length: 100,
                                     transcript: [TranscriptSegment(start: 1, end: 2, text: "x")])
        let source = try makeSession(in: root.url, name: "b", start: 200, length: 100,
                                     transcript: [TranscriptSegment(start: 1, end: 2, text: "y")])
        struct Crash: Error {}
        #expect(throws: Crash.self) { try SessionMerge.merge(source, into: target, trash: { _ in throw Crash() }) }
        #expect(exists(target.url.appending(path: SessionMerge.journalName)))

        let failed = SessionMerge.recoverUnfinished(in: root.url, trash: trash)
        #expect(failed.isEmpty)
        #expect(!exists(source.url))
        #expect(!exists(target.url.appending(path: SessionMerge.journalName)))
        let metadata = try target.loadMetadata()
        #expect(metadata.parts.count == 2)
        #expect(metadata.transcription == .done)
    }
}

struct SessionOperationsMergeTests {
    @Test func mergeHoldsBothSessionsOrNone() {
        var operations = SessionOperations()
        let a = URL(filePath: "/s/a"), b = URL(filePath: "/s/b")
        let summary = operations.begin(.summary, for: b)
        let busy = operations.begin(.merge, for: [a, b])
        #expect(summary && !busy)
        #expect(operations.isIdle(a))
        operations.end(.summary, for: b)
        let merge = operations.begin(.merge, for: [a, b])
        #expect(merge)
        #expect(operations.operation(for: a) == .merge && operations.operation(for: b) == .merge)
    }
}

struct SessionRecoveryTests {
    @Test func anInterruptedRecordingGetsItsEndFromTheMedia() async throws {
        let root = try TemporaryDirectory()
        let session = SessionFolder(url: root.url.appending(path: "a"))
        try session.createDirectories()
        var metadata = SessionMetadata(startedAt: Date(timeIntervalSince1970: 0))
        metadata.transcription = .running
        try session.save(metadata)

        let interrupted = try await SessionRecovery.recover(session) { url in
            switch url.lastPathComponent {
            case "recording.mov": 120
            case "mic.m4a": 118
            default: nil
            }
        }
        #expect(interrupted)
        let recovered = try session.loadMetadata()
        #expect(recovered.endedAt == Date(timeIntervalSince1970: 120))
        #expect(recovered.interrupted && recovered.endReason == .crash)
        #expect(recovered.audioTracks.map(\.file) == ["audio/mic.m4a"])
        #expect(recovered.transcription == .pending)
        #expect(try await !SessionRecovery.recover(session) { _ in nil })
    }

    @Test func unreadableMediaUsesTheHeartbeat() async throws {
        let root = try TemporaryDirectory()
        let session = try makeSession(in: root.url, name: "a", start: 0, length: 60)
        try session.convertToParts()
        try session.updateMetadata {
            var part = SessionPart(folder: "parts/02", startedAt: Date(timeIntervalSince1970: 100), origin: .continued)
            part.video = "recording.mov"
            part.lastAliveAt = Date(timeIntervalSince1970: 150)
            part.audioTracks = [AudioTrackInfo(file: "audio/mic.m4a", speaker: .me, offset: 0)]
            $0.parts.append(part)
            $0.endedAt = nil
        }
        #expect(try await SessionRecovery.recover(session) { _ in nil })
        let recovered = try session.loadMetadata()
        #expect(recovered.parts[1].endedAt == Date(timeIntervalSince1970: 150))
        #expect(recovered.parts[1].interrupted)
        #expect(recovered.parts[1].audioTracks.isEmpty)
        #expect(recovered.isInterrupted)
        #expect(recovered.endedAt == Date(timeIntervalSince1970: 150))
        #expect(!recovered.parts[0].interrupted)
    }
}
