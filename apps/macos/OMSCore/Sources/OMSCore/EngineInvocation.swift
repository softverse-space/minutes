import Foundation

/// Command-line arguments for each summary engine. Pure functions, so the safety rules
/// (no tools, read-only sandbox, restricted Bash) are covered by tests.
public enum EngineInvocation {
    /// `opencode run` with an agent. The transcript is an attached file; the prompt is the message.
    public static func openCode(agent: String, title: String, transcriptPath: String, model: String, prompt: String) -> [String] {
        var arguments = ["run", "--agent", agent, "--title", title, "-f", transcriptPath]
        if let model = nonEmpty(model) { arguments += ["-m", model] }
        arguments.append(prompt)
        return arguments
    }

    /// Frame access for one summary run: the installed frame tool and the `frames` folder of the session.
    public struct FrameAccess: Sendable, Equatable {
        public var toolPath: String
        public var framesPath: String

        public init(toolPath: String, framesPath: String) {
            self.toolPath = toolPath
            self.framesPath = framesPath
        }
    }

    /// `claude -p`: no session file, no MCP servers, no slash commands. Without frames it gets no tools.
    /// With frames it has `Read` and `Bash`. The allow rules cover only the `frames` folder and the frame tool;
    /// without a prompt, Claude denies every other command and every read outside its working folder.
    public static func claude(systemPrompt: String, model: String, frames: FrameAccess?) -> [String] {
        var arguments = ["-p", "--output-format", "text", "--no-session-persistence",
                         "--strict-mcp-config", "--disable-slash-commands", "--system-prompt", systemPrompt]
        if let model = nonEmpty(model) { arguments += ["--model", model] }
        if let frames {
            // `//` starts an absolute path in a Claude Code permission rule.
            arguments += ["--tools", "Read,Bash", "--allowedTools",
                          "Read(/\(frames.framesPath)/**)", "Bash(\"\(frames.toolPath)\":*)"]
        } else {
            arguments += ["--tools", ""]
        }
        return arguments
    }

    /// `codex exec` reading the prompt from stdin. The sandbox is read-only and works in the session folder.
    /// When the model may cut frames, the sandbox is workspace-write and the workspace is only the `frames`
    /// folder, so Codex cannot change the transcript or `session.json`. The final answer goes to `answerPath`.
    public static func codex(sessionPath: String, framesPath: String?, answerPath: String, model: String) -> [String] {
        var arguments = ["exec", "--skip-git-repo-check", "--ephemeral", "--color", "never",
                         "--sandbox", framesPath != nil ? "workspace-write" : "read-only",
                         "--cd", framesPath ?? sessionPath, "--output-last-message", answerPath]
        if let model = nonEmpty(model) { arguments += ["--model", model] }
        arguments.append("-")
        return arguments
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
