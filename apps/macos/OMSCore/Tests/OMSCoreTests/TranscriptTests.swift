import Foundation
import Testing
@testable import OMSCore

struct TranscriptTests {
    @Test func mergeSortsAndAppliesOffsetAndSpeaker() throws {
        let mic = [TranscriptSegment(start: 5, end: 6, text: " Ahoj ")]
        let system = [TranscriptSegment(start: 1, end: 2, text: "Dobrý deň"), TranscriptSegment(start: 3, end: 4, text: "  ")]
        let transcript = Transcript.merged(engine: "test", language: "sk", tracks: [
            (speaker: .me, offset: 0.5, segments: mic),
            (speaker: .others, offset: 0, segments: system),
        ])
        #expect(transcript.segments.map(\.text) == ["Dobrý deň", "Ahoj"])
        try #require(transcript.segments.count == 2)
        #expect(transcript.segments[1].start == 5.5)
        #expect(transcript.markdown() == "[00:00:01] others: Dobrý deň\n[00:00:05] me: Ahoj\n")
    }

    @Test func srtFormat() {
        let transcript = Transcript(engine: "t", segments: [TranscriptSegment(start: 1, end: 2.5, text: "Test")])
        #expect(transcript.srt() == "1\n00:00:01,000 --> 00:00:02,500\nTest\n")
    }

    @Test func vttFormatHasHeaderAndDotSeparator() {
        let transcript = Transcript(engine: "t", segments: [TranscriptSegment(start: 1, end: 2.5, text: "Test")])
        #expect(transcript.vtt().hasPrefix("WEBVTT"))
        #expect(transcript.vtt().contains("00:00:01.000 --> 00:00:02.500\nTest\n"))
    }

    @Test func parsesVerboseJSON() throws {
        let json = #"{"text":"a b","language":"sk","segments":[{"start":0,"end":1.5,"text":"a"},{"start":1.5,"end":3,"text":"b"}]}"#
        let result = try TranscriptionResponseParser.parse(Data(json.utf8))
        #expect(result.language == "sk")
        #expect(result.segments.count == 2)
    }

    @Test func parsesPlainJSONWithoutSegments() throws {
        let result = try TranscriptionResponseParser.parse(Data(#"{"text":"iba text","duration":12}"#.utf8))
        #expect(result.segments == [TranscriptSegment(start: 0, end: 12, text: "iba text")])
    }

    @Test func emptyTextGivesNoSegments() throws {
        let result = try TranscriptionResponseParser.parse(Data(#"{"text":"   "}"#.utf8))
        #expect(result.segments.isEmpty)
    }

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) { try TranscriptionResponseParser.parse(Data("not json".utf8)) }
    }
}
