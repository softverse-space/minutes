import Testing
@testable import OMSCore

struct MarkdownHTMLTests {
    @Test func headingsAndParagraphs() {
        let html = MarkdownHTML.body("# Sprint review – 18. 11.\n\nFirst line\nsecond line\n\n## Tasks ##")
        #expect(html.contains("<h1>Sprint review – 18. 11.</h1>"))
        #expect(html.contains("<p>First line<br>\nsecond line</p>"))
        #expect(html.contains("<h2>Tasks</h2>"))
    }

    @Test func inlineFormatting() {
        let html = MarkdownHTML.inline("**Owner:** Jana, *draft*, `a*b*c`, [Jira](https://example.com/x?a=1&b=2)")
        #expect(html.contains("<strong>Owner:</strong>"))
        #expect(html.contains("<em>draft</em>"))
        #expect(html.contains("<code style=\"background: #f0f0f0;\">a*b*c</code>"))
        #expect(html.contains("<a href=\"https://example.com/x?a=1&amp;b=2\">Jira</a>"))
    }

    @Test func escapesHTMLAndUnsafeLinks() {
        let html = MarkdownHTML.inline("<script>x</script> [click](javascript:alert(1)) snake_case_name 2 * 3 * 4")
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<a "))
        #expect(html.contains("snake_case_name"))
        #expect(!html.contains("<em>"))
    }

    @Test func nestedAndOrderedLists() {
        let html = MarkdownHTML.body("- **Topic A:**\n  - point 1\n  - point 2\n- Topic B\n\n3. third\n4. fourth")
        #expect(html.contains("<ul><li><strong>Topic A:</strong><ul><li>point 1</li><li>point 2</li></ul>\n</li><li>Topic B</li></ul>"))
        #expect(html.contains("<ol start=\"3\"><li>third</li><li>fourth</li></ol>"))
    }

    @Test func listContinuationAndLooseList() {
        let html = MarkdownHTML.body("- first\n  continues\n\n- second")
        #expect(html.contains("<ul><li>first continues</li><li>second</li></ul>"))
    }

    @Test func table() {
        let markdown = """
        | ID | What to do | Owner |
        |----|:-----------|------:|
        | 1 | Send the **offer** | Jana |
        | 2 | Check a\\|b | TBA |
        """
        let html = MarkdownHTML.body(markdown)
        #expect(html.contains("<table"))
        #expect(html.contains(">What to do</th>"))
        #expect(html.contains("text-align: right;\">Jana</td>"))
        #expect(html.contains("Send the <strong>offer</strong>"))
        #expect(html.contains(">Check a|b</td>"))
        #expect(html.components(separatedBy: "<tr>").count == 4)
    }

    @Test func quoteCodeAndRule() {
        let html = MarkdownHTML.body("> quoted **text**\n\n```\nlet x = <y>\n```\n\n---\n\n* * *")
        #expect(html.contains("<blockquote"))
        #expect(html.contains("<p>quoted <strong>text</strong></p>"))
        #expect(html.contains("<code>let x = &lt;y&gt;</code></pre>"))
        #expect(html.components(separatedBy: "<hr>").count == 3)
        #expect(!html.contains("<ul>"))
    }

    @Test func documentHasCharset() {
        #expect(MarkdownHTML.document("Á").contains("<meta charset=\"utf-8\">"))
    }
}

struct PromptPreviewTests {
    @Test func previewHasAllParts() {
        let text = PromptPreview.render(systemPrompt: "RULES\n", taskPrompt: "TASK", engine: "OpenCode", model: "qwen3",
                                        transcriptFile: "transcript.md", transcriptWords: 1200)
        #expect(text.contains("Model: OpenCode · qwen3"))
        #expect(text.contains("# 1. System prompt\n\nRULES\n"))
        #expect(text.contains("# 2. Task\n\nTASK"))
        #expect(text.contains("`transcript.md` (1200 words)"))
    }

    @Test func previewWithoutTranscript() {
        let text = PromptPreview.render(systemPrompt: "R", taskPrompt: "T", engine: "Claude", model: "",
                                        transcriptFile: "transcript.md", transcriptWords: nil)
        #expect(text.contains("Model: Claude\n"))
        #expect(text.contains("no transcript yet"))
    }

    @Test func wordCount() {
        #expect(PromptPreview.wordCount("one  two\nthree\t four") == 4)
    }
}
