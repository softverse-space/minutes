import Foundation
import Testing
@testable import OMSCore

struct TemplateTests {
    let retro = """
    ---
    id: retro
    name: Sprint Retrospective
    frames: auto
    detail: stredna
    language: en
    ---
    Body

    ---

    ## Action Items
    """

    @Test func parsesFrontMatterAndKeepsRulesInBody() throws {
        let template = try SummaryTemplate.parse(retro)
        #expect(template.id == "retro")
        #expect(template.language == "en")
        #expect(template.detail == .medium)
        #expect(template.body.contains("## Action Items"))
        #expect(template.body.contains("---"))
    }

    @Test func autoLanguageIsNilAndNameFallsBackToID() throws {
        let template = try SummaryTemplate.parse("---\nid: x\nlanguage: auto\n---\nB")
        #expect(template.language == nil)
        #expect(template.name == "x")
    }

    @Test func acceptsWindowsLineEndingsAndIgnoresUnknownValues() throws {
        let template = try SummaryTemplate.parse("---\r\nid: x\r\nframes: sometimes\r\ndetail: huge\r\n---\r\nB")
        #expect(template.id == "x")
        #expect(template.frames == .auto)
        #expect(template.detail == nil)
    }

    @Test func rejectsMissingFrontMatter() {
        #expect(throws: SummaryTemplate.ParseError.missingFrontMatter) { try SummaryTemplate.parse("no") }
    }

    @Test func rejectsMissingID() {
        #expect(throws: SummaryTemplate.ParseError.missingField("id")) { try SummaryTemplate.parse("---\nname: X\n---\nB") }
    }

    @Test func parsesDetailLevels() {
        let catalog = DetailLevelCatalog.parse("<!-- c -->\n\n## strucna\nA\n\n## detailna\nB\nC\n")
        #expect(catalog.instructions[.brief] == "A")
        #expect(catalog.instructions[.detailed] == "B\nC")
        #expect(catalog.instructions[.medium] == nil)
    }

    @Test func userTemplatesOverrideBundledAndStandardComesFirst() throws {
        let root = try TemporaryDirectory()
        let bundled = root.url.appending(path: "a"), user = root.url.appending(path: "b")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "---\nid: retro\n---\nX".write(to: bundled.appending(path: "retro.md"), atomically: true, encoding: .utf8)
        try "---\nid: standard\n---\nOld".write(to: bundled.appending(path: "standard.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: bundled.appending(path: "_detail-levels.md"), atomically: true, encoding: .utf8)
        try "no front matter".write(to: user.appending(path: "broken.md"), atomically: true, encoding: .utf8)
        try "---\nid: standard\n---\nNew".write(to: user.appending(path: "mine.md"), atomically: true, encoding: .utf8)

        let templates = TemplateLoader.load(from: [bundled, user])

        #expect(templates.map(\.id) == ["standard", "retro"])
        #expect(templates.first?.body == "New")
    }
}
