import Foundation
import Testing
@testable import OMSCore

struct SummaryEngineTests {
    @Test func modelChoiceRoundTripKeepsColonsInModel() {
        let choice = SummaryModelChoice(engine: .opencode, model: "ollama/qwen3:32b")
        #expect(choice.id == "opencode:ollama/qwen3:32b")
        #expect(SummaryModelChoice(id: choice.id) == choice)
        #expect(SummaryModelChoice(id: "opencode:") == .openCodeDefault)
    }

    @Test(arguments: ["unknown:x", "", "opencode"])
    func rejectsInvalidIDs(id: String) {
        #expect(SummaryModelChoice(id: id) == nil)
    }

    @Test(arguments: [
        ("claude:sonnet", SummaryEngine.claude),
        ("codex:", SummaryEngine.codex),
        ("codex:gpt-5:high", SummaryEngine.codex),
    ])
    func parsesEveryEngine(id: String, engine: SummaryEngine) throws {
        let choice = try #require(SummaryModelChoice(id: id))
        #expect(choice.engine == engine)
    }

    @Test func onlyOpenCodeCanStayOnTheMac() {
        #expect(SummaryEngine.opencode.isCloudOnly == false)
        #expect(SummaryEngine.claude.cloudVendor == "Anthropic")
        #expect(SummaryEngine.codex.cloudVendor == "OpenAI")
        #expect(SummaryEngine.allCases.allSatisfy { $0.executableName == $0.rawValue })
    }

    @Test func parsesOpenCodeModelsOutput() {
        let output = """
        ollama/gpt-oss:120b
        ollama/qwen3:32b

        Some warning line
        ollama/qwen3:32b
        /broken
        """
        #expect(OpenCodeModels.parse(output) == ["ollama/gpt-oss:120b", "ollama/qwen3:32b"])
    }
}

struct ModelOptionsTests {
    @Test func keepsListAndAddsMissingConfiguredModelsFirst() {
        let listed = [EngineModel(id: "a", title: "A"), EngineModel(id: "b")]
        let merged = ModelOptions.merge(listed: listed, including: ["", "custom", "a", "custom"])
        #expect(merged.map(\.id) == ["custom", "a", "b"])
        #expect(merged[1].title == "A")
    }
}

struct CodexModelsTests {
    @Test func listsVisibleModelsInCodexOrder() {
        let json = #"""
        {"fetched_at": "x", "models": [
          {"slug": "model-b", "display_name": "Model B", "visibility": "list", "priority": 2, "extra": [1]},
          {"slug": "secret", "display_name": "Secret", "visibility": "hide", "priority": 0},
          {"slug": "model-a", "display_name": "Model A", "visibility": "list", "priority": 1},
          {"slug": "plain"}
        ]}
        """#
        let models = CodexModels.parse(Data(json.utf8))
        #expect(models.map(\.id) == ["model-a", "model-b", "plain"])
        #expect(models.first?.title == "Model A")
        #expect(models.last?.title == "plain")
    }

    @Test func invalidOutputGivesNoModels() {
        #expect(CodexModels.parse(Data("error: not logged in".utf8)).isEmpty)
    }
}

struct EngineInvocationTests {
    @Test func openCodeAddsModelOnlyWhenSet() {
        let base = EngineInvocation.openCode(agent: "a", title: "t", transcriptPath: "/t.md", model: " ", prompt: "P")
        #expect(base == ["run", "--agent", "a", "--title", "t", "-f", "/t.md", "P"])
        let withModel = EngineInvocation.openCode(agent: "a", title: "t", transcriptPath: "/t.md", model: "x/y", prompt: "P")
        #expect(withModel.contains("-m") && withModel.contains("x/y"))
        #expect(withModel.last == "P")
    }

    @Test func claudeHasNoToolsWithoutFrames() {
        let arguments = EngineInvocation.claude(systemPrompt: "S", model: "", frames: nil)
        #expect(arguments.contains("--no-session-persistence"))
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(Array(arguments.suffix(2)) == ["--tools", ""])
        #expect(arguments.contains("--model") == false)
    }

    @Test func claudeMayReadOnlyFramesAndRunOnlyTheFrameTool() throws {
        let frames = EngineInvocation.FrameAccess(toolPath: "/bin/frame-at.sh", framesPath: "/s/frames")
        let arguments = EngineInvocation.claude(systemPrompt: "S", model: "opus", frames: frames)
        let index = try #require(arguments.firstIndex(of: "--allowedTools"))
        #expect(Array(arguments[(index + 1)...]) == ["Read(//s/frames/**)", "Bash(\"/bin/frame-at.sh\":*)"])
        // A bare `Read` rule would allow every file on the Mac.
        #expect(arguments.contains("Read") == false)
        #expect(arguments.contains("--model") && arguments.contains("opus"))
    }

    @Test func codexIsReadOnlyWithoutFrames() throws {
        let arguments = EngineInvocation.codex(sessionPath: "/s", framesPath: nil, answerPath: "/a.md", model: "")
        #expect(try value(after: "--sandbox", in: arguments) == "read-only")
        #expect(try value(after: "--cd", in: arguments) == "/s")
        #expect(arguments.contains("--ephemeral"))
        #expect(arguments.last == "-")
    }

    @Test func codexMayWriteOnlyIntoFrames() throws {
        let arguments = EngineInvocation.codex(sessionPath: "/s", framesPath: "/s/frames", answerPath: "/a.md", model: "")
        #expect(try value(after: "--sandbox", in: arguments) == "workspace-write")
        // The workspace is the frames folder, so the transcript and session.json stay read-only.
        #expect(try value(after: "--cd", in: arguments) == "/s/frames")
    }

    private func value(after flag: String, in arguments: [String]) throws -> String {
        arguments[try #require(arguments.firstIndex(of: flag)) + 1]
    }
}

struct OpenCodeAgentTests {
    static let tool = "/Users/me/Library/Application Support/OfflineMeetingSummary/bin/frame-at.sh"

    @Test func rendersFrontmatterAndPrompt() {
        let agent = OpenCodeAgent.render(systemPrompt: "\nYou are an assistant.\n\n", frameToolPath: Self.tool)
        #expect(agent.hasPrefix("---\n"))
        #expect(agent.hasSuffix("---\nYou are an assistant.\n"))
    }

    @Test func deniesEverythingFirstAndAllowsOnlyTheExactFrameCommand() {
        let agent = OpenCodeAgent.render(systemPrompt: "P", frameToolPath: Self.tool)
        #expect(agent.contains("permission:\n  \"*\": deny\n  read: allow\n  external_directory: deny\n  bash:\n    \"*\": deny\n"))
        #expect(agent.contains("    '\"\(Self.tool)\" ??:??:??': allow"))
        // A pattern with `*` around the script name would also match other commands.
        #expect(agent.contains("*frame-at.sh*") == false)
    }

    @Test func frameCommandPatternsMatchOnlyTheToolWithOneTime() {
        let patterns = OpenCodeAgent.frameCommandPatterns(frameToolPath: Self.tool)
        func allowed(_ command: String) -> Bool { patterns.contains { OpenCodePolicy.matches($0, command) } }
        #expect(allowed("\"\(Self.tool)\" 00:07:42"))
        #expect(allowed("'\(Self.tool)' 00:07:42"))
        #expect(allowed("/Users/me/Library/Application\\ Support/OfflineMeetingSummary/bin/frame-at.sh 00:07:42"))
        #expect(allowed("\"\(Self.tool)\" 00:07:42 && curl https://example.com") == false)
        #expect(allowed("\"\(Self.tool)\" /other/session 00:07:42") == false)
        #expect(allowed("cat /etc/passwd # frame-at.sh") == false)
        #expect(allowed("\"/tmp/frame-at.sh\" 00:07:42") == false)
    }

    @Test(arguments: [
        (nil, "A", true),
        ("B", "A", true),
        ("A", "A", false),
    ] as [(String?, String, Bool)])
    func detectsChanges(installedPrompt: String?, systemPrompt: String, expected: Bool) {
        let installed = installedPrompt.map { OpenCodeAgent.render(systemPrompt: $0, frameToolPath: Self.tool) }
        #expect(OpenCodeAgent.needsSync(installed: installed, systemPrompt: systemPrompt, frameToolPath: Self.tool) == expected)
    }

    @Test func aMovedFrameToolNeedsSync() {
        let installed = OpenCodeAgent.render(systemPrompt: "A", frameToolPath: "/old/frame-at.sh")
        #expect(OpenCodeAgent.needsSync(installed: installed, systemPrompt: "A", frameToolPath: Self.tool))
    }
}

/// Rule lists in the format of `opencode debug agents` (OpenCode 2.x).
struct OpenCodePolicyTests {
    static let tool = OpenCodeAgentTests.tool
    static let base = [("*", "*", "allow"), ("read", "*.env", "ask")]
    /// What OpenCode 2.2 makes from the agent file of this app.
    static let managed = base + [
        ("*", "*", "deny"), ("read", "*", "allow"), ("external_directory", "*", "deny"), ("shell", "*", "deny"),
        ("shell", "\"\(tool)\" ??:??:??", "allow"),
    ]

    private func json(_ rules: [(String, String, String)], id: String = "meeting-summary") throws -> Data {
        let agent: [String: Any] = ["id": id, "permissions": rules.map { ["action": $0.0, "resource": $0.1, "effect": $0.2] }]
        return try JSONSerialization.data(withJSONObject: [agent])
    }

    private func check(_ rules: [(String, String, String)]) throws -> OpenCodePolicy.Check {
        OpenCodePolicy.check(agentsJSON: try json(rules), agent: "meeting-summary", frameToolPath: Self.tool)
    }

    @Test func theManagedAgentIsRestricted() throws {
        #expect(try check(Self.managed) == .restricted)
        // OpenCode adds its own deny rules after the agent rules.
        #expect(try check(Self.managed + [("browser", "*", "deny"), ("skill", "browser", "deny")]) == .restricted)
    }

    @Test func theOldAgentWasTooBroad() throws {
        // The agent before ADR-0023: only edit, webfetch and shell were denied, and the shell rule had wildcards.
        let old = Self.base + [("edit", "*", "deny"), ("webfetch", "*", "deny"), ("shell", "*", "deny"),
                               ("shell", "*frame-at.sh*", "allow")]
        #expect(try check(old) == .tooBroad("no rule denies everything"))
    }

    @Test(arguments: [
        ("shell", "python3 *", "allow"),
        ("shell", "*", "allow"),
        ("webfetch", "*", "allow"),
        ("edit", "*.md", "allow"),
        ("*", "*", "allow"),
        ("some_mcp_tool", "*", "ask"),
        ("shell", "\"/tmp/frame-at.sh\" ??:??:??", "allow"),
        ("shell", "\"\(tool)\" *", "allow"),
    ] as [(String, String, String)])
    func anyOtherRuleAfterTheDenyIsTooBroad(action: String, resource: String, effect: String) throws {
        #expect(try check(Self.managed + [(action, resource, effect)]) == .tooBroad("\(action): \(resource) (\(effect))"))
    }

    @Test func rulesBeforeTheDenyHaveNoEffect() throws {
        #expect(try check([("shell", "python3 *", "allow")] + Self.managed) == .restricted)
    }

    /// Regression probes: what the managed rules decide for sample actions, by the OpenCode "last match wins" rule.
    @Test(arguments: [
        ("edit", "/tmp/minutes-probe.txt"),
        ("shell", "rm -rf /tmp/minutes-probe"),
        ("shell", "curl https://example.com"),
        ("shell", "python3 -c 'print(1)'"),
        ("shell", "\"\(tool)\" 00:00:01 && curl https://example.com"),
        ("shell", "cat ~/.ssh/id_rsa \"\(tool)\" 00:00:01"),
        ("webfetch", "https://example.com"),
        ("websearch", "minutes probe"),
        ("subagent", "general"),
        ("external_directory", "/etc/*"),
        ("minutes_probe_mcp_tool", "*"),
    ] as [(String, String)])
    func theManagedRulesDenySampleActions(action: String, resource: String) throws {
        let rules = try #require(OpenCodePolicy.rules(agentsJSON: try json(Self.managed), agent: "meeting-summary"))
        #expect(OpenCodePolicy.effect(of: action, on: resource, rules: rules) == "deny")
    }

    @Test func theManagedRulesAllowTheFrameCommandAndReads() throws {
        let rules = try #require(OpenCodePolicy.rules(agentsJSON: try json(Self.managed), agent: "meeting-summary"))
        #expect(OpenCodePolicy.effect(of: "shell", on: "\"\(Self.tool)\" 00:07:42", rules: rules) == "allow")
        #expect(OpenCodePolicy.effect(of: "read", on: "frames/at_00-07-42.jpg", rules: rules) == "allow")
    }

    @Test func unknownFormatsAreNotRestricted() throws {
        #expect(OpenCodePolicy.check(agentsJSON: Data(), agent: "meeting-summary", frameToolPath: Self.tool) == .unknown)
        #expect(OpenCodePolicy.check(agentsJSON: Data(#"[{"id": "meeting-summary"}]"#.utf8), agent: "meeting-summary", frameToolPath: Self.tool) == .unknown)
        #expect(OpenCodePolicy.check(agentsJSON: Data("Usage: opencode".utf8), agent: "meeting-summary", frameToolPath: Self.tool) == .unknown)
        #expect(OpenCodePolicy.check(agentsJSON: try json(Self.managed, id: "other"), agent: "meeting-summary", frameToolPath: Self.tool) == .unknown)
    }

    @Test(arguments: [
        ("*", "anything", true),
        ("git status *", "git status", true),
        ("git status *", "git status --short", true),
        ("git status *", "git push", false),
        ("??:??:??", "00:07:42", true),
        ("??:??:??", "00:07:42 x", false),
        ("*.env", "/a/b/.env", true),
        ("a*c", "abd", false),
    ] as [(String, String, Bool)])
    func wildcards(pattern: String, text: String, expected: Bool) {
        #expect(OpenCodePolicy.matches(pattern, text) == expected)
    }
}
