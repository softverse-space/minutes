import Foundation
import Testing
@testable import OMSCore

struct PromptBuilderTests {
    @Test func promptContainsAllParts() throws {
        let template = try SummaryTemplate.parse("---\nid: standard\nframes: auto\n---\nTemplate body")
        let request = SummaryRequest(template: template, detail: .brief, language: "en", extraInstruction: "Focus on the database",
                                     meetingDate: Date(timeIntervalSince1970: 0), timeZone: .utc,
                                     frameToolPath: "/bin/frame-at.sh")
        let prompt = PromptBuilder.build(request, details: DetailLevelCatalog(instructions: [.brief: "BRIEF"]))
        #expect(prompt.contains("Template body"))
        #expect(prompt.contains("BRIEF"))
        #expect(prompt.contains("English (en)"))
        #expect(prompt.contains("Focus on the database"))
        #expect(prompt.contains("`\"/bin/frame-at.sh\" <hh:mm:ss>`"))
        #expect(prompt.contains(PromptBuilder.topicMarker))
    }

    @Test func customInstructionWithoutFramesOrExtra() {
        let request = SummaryRequest(template: nil, customInstruction: "Only the tasks", detail: .medium, language: "sk",
                                     extraInstruction: "  ", meetingDate: Date(), frameToolPath: nil)
        let prompt = PromptBuilder.build(request, details: DetailLevelCatalog(instructions: [:]))
        #expect(prompt.contains("Only the tasks"))
        #expect(prompt.contains("not available"))
        #expect(prompt.contains("Additional instruction") == false)
    }

    @Test func templateWithFramesNeverGetsNoFrameTool() throws {
        let template = try SummaryTemplate.parse("---\nid: t\nframes: never\n---\nB")
        let request = SummaryRequest(template: template, detail: .medium, language: "sk", meetingDate: Date(),
                                     frameToolPath: "/bin/frame-at.sh")
        let prompt = PromptBuilder.build(request, details: DetailLevelCatalog(instructions: [:]))
        #expect(prompt.contains("frame-at.sh") == false)
    }

    /// 23:30 UTC on 13 November is already 14 November in Bratislava.
    @Test func meetingDateUsesTheSessionTimeZone() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-13T23:30:00Z"))
        let request = SummaryRequest(template: nil, customInstruction: "X", detail: .medium, language: "sk",
                                     meetingDate: date, timeZone: try #require(TimeZone(identifier: "Europe/Bratislava")),
                                     frameToolPath: nil)
        #expect(PromptBuilder.build(request, details: DetailLevelCatalog(instructions: [:])).contains("2026-11-14"))
    }
}

struct SummaryOutputTests {
    @Test func extractsTopic() {
        let (topic, body) = SummaryOutput.extractTopic(from: "\n<!-- topic: Sprint Planning Q4 -->\n# Minutes\n")
        #expect(topic == "sprint_planning_q4")
        #expect(body == "# Minutes\n")
    }

    @Test func missingTopicKeepsBody() {
        let (topic, body) = SummaryOutput.extractTopic(from: "# Minutes")
        #expect(topic == nil)
        #expect(body == "# Minutes\n")
    }

    @Test func markerAfterTheFifthLineIsNotATopic() {
        let output = "a\nb\nc\nd\ne\n<!-- topic: late -->\n"
        #expect(SummaryOutput.extractTopic(from: output).topic == nil)
    }

    @Test(arguments: [
        ("Ručné poistné – daň", "rucne_poistne_dan"),
        ("one two three four five", "one_two_three_four"),
        ("", ""),
        ("— !! —", ""),
    ])
    func slugify(text: String, expected: String) {
        #expect(SummaryOutput.slugify(text) == expected)
    }
}

@Test func requestedOutputName() {
    let result = SummaryOutput.extract(from: "<!-- topic: retro -->\n<!-- filename: 2026-11-13_meeting_sumamry_v3_candidate.md -->\n# Minutes")
    #expect(result.topic == "retro")
    #expect(result.fileName == "2026-11-13_meeting_sumamry_v3_candidate.md")
    #expect(result.body == "# Minutes\n")
    let name = SessionNaming.summaryFileName(date: Date(), topic: "retro", existing: [], proposedName: result.fileName)
    #expect(name == result.fileName)
    #expect(SessionNaming.summaryFileName(date: Date(), topic: "retro", existing: [name.uppercased()], proposedName: name) == "2026-11-13_meeting_sumamry_v3_candidate_v2.md")
}

@Test func invalidOutputNames() {
    for name in ["../escape.md", "/tmp/file.md", "folder\\file.md", ".hidden.md", "file.txt", "a\nb.md", "a:b.md", String(repeating: "x", count: 221) + ".md"] {
        #expect(SessionNaming.validSummaryFileName(name) == nil)
        #expect(SessionNaming.summaryFileName(date: Date(), topic: "retro", existing: [], proposedName: name).hasSuffix("_meetingsummary_retro.md"))
    }
    #expect(SummaryOutput.extract(from: "# Minutes").fileName == nil)
}
