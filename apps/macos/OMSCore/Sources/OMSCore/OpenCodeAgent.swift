import Foundation

/// The provider-neutral system prompt for meeting summaries.
/// The default text lives in `apps/macos/prompts/meeting-summary.md`. The user edits a copy (ADR-0025).
/// Each LLM provider adapter turns it into its own format.
public enum SystemPrompt {
    public static let name = "meeting-summary"

    public enum CopyAction: Equatable, Sendable {
        /// Leave the user's copy as it is.
        case keep
        /// Write the bundled default to the user's copy.
        case writeDefault
    }

    /// Decides what to do with the user's copy at app start (ADR-0025).
    ///
    /// The app replaces the copy only when it is missing, empty or still equal to the default that the app wrote last time.
    /// Thus a new default gets to users who did not edit the prompt, and an edited prompt stays.
    public static func copyAction(userCopy: String?, bundledDefault: String, lastWrittenDefaultDigest: String?) -> CopyAction {
        guard let userCopy, !userCopy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .writeDefault }
        if userCopy == bundledDefault { return .keep }
        return digest(userCopy) == lastWrittenDefaultDigest ? .writeDefault : .keep
    }

    /// The text that the summary uses: the user's copy, or the bundled default when the copy is missing or empty.
    public static func effective(userCopy: String?, bundledDefault: String?) -> String? {
        if let userCopy, !userCopy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return userCopy }
        return bundledDefault
    }

    /// Stable digest of a prompt text (FNV-1a, 64 bit). It only detects changes; it is not a security check.
    public static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Adapter for OpenCode: renders the system prompt as an OpenCode agent file.
public enum OpenCodeAgent {
    /// The agent name that the app manages. The app overwrites this agent file.
    public static let managedName = SystemPrompt.name

    /// Agent file with OpenCode permissions and the system prompt as its body (ADR-0023).
    ///
    /// Everything is denied first. Then the agent may read files in the session folder and run
    /// the installed frame tool with one `hh:mm:ss` argument. The file uses the OpenCode 1.x
    /// `permission` syntax, because OpenCode 2.x converts it and OpenCode 1.x ignores the 2.x syntax.
    public static func render(systemPrompt: String, frameToolPath: String) -> String {
        let shellRules = frameCommandPatterns(frameToolPath: frameToolPath)
            .map { "    \(yamlKey($0)): allow" }
            .joined(separator: "\n")
        return """
        ---
        # Managed by OfflineMeetingSummary. The app overwrites this file.
        # Source: apps/macos/prompts/meeting-summary.md. Change the prompt there.
        description: Writes meeting minutes from a transcript and a template. May cut frames from the video.
        mode: primary
        temperature: 0.2
        permission:
          "*": deny
          read: allow
          external_directory: deny
          bash:
            "*": deny
        \(shellRules)
        ---
        \(systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines))

        """
    }

    /// `true` when the installed file is missing or differs from the rendered agent.
    public static func needsSync(installed: String?, systemPrompt: String, frameToolPath: String) -> Bool {
        installed != render(systemPrompt: systemPrompt, frameToolPath: frameToolPath)
    }

    /// Shell command patterns for the frame tool: the exact path in each common quoting and a time of 8 characters.
    /// `?` matches one character, so a pattern cannot match a longer command with other arguments.
    static func frameCommandPatterns(frameToolPath path: String) -> [String] {
        let time = "??:??:??"
        return [
            "\"\(path)\" \(time)",
            "'\(path)' \(time)",
            "\(path.replacingOccurrences(of: " ", with: "\\ ")) \(time)",
        ]
    }

    /// A YAML single-quoted scalar: only `'` needs an escape.
    private static func yamlKey(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "''"))'"
    }
}

/// Checks the permissions that the installed OpenCode gives the agent, from `opencode debug agents`.
/// The agent file is only a request. The user's OpenCode version and configuration decide the result.
public enum OpenCodePolicy {
    public enum Check: Equatable, Sendable {
        /// The agent may only read files and run the exact frame command.
        case restricted
        /// The agent may do more than the app needs. The value names the first rule that is not on the allowed list.
        case tooBroad(String)
        /// The output has no permission list for the agent (OpenCode 1.x or an unknown format).
        /// The caller must treat it as a refusal.
        case unknown
    }

    struct Rule: Decodable, Equatable {
        let action: String
        let resource: String
        let effect: String
    }

    private struct Agent: Decodable {
        let id: String
        let permissions: [Rule]?
    }

    /// Checks the whole rule list, not sample commands: a sample cannot find a rule such as `shell: python3 *`.
    ///
    /// OpenCode uses the last matching rule. So the list must have a rule that denies everything, and each rule
    /// after it must be a `deny` or one of the rules that the app wrote. The rules before it have no effect.
    public static func check(agentsJSON: Data, agent: String, frameToolPath: String) -> Check {
        guard let rules = rules(agentsJSON: agentsJSON, agent: agent), !rules.isEmpty else { return .unknown }
        guard let denyAll = rules.lastIndex(of: Rule(action: "*", resource: "*", effect: "deny")) else {
            return .tooBroad("no rule denies everything")
        }
        let allowed = [Rule(action: "read", resource: "*", effect: "allow")]
            + OpenCodeAgent.frameCommandPatterns(frameToolPath: frameToolPath).map { Rule(action: "shell", resource: $0, effect: "allow") }
        for rule in rules[(denyAll + 1)...] where rule.effect != "deny" && !allowed.contains(rule) {
            return .tooBroad("\(rule.action): \(rule.resource) (\(rule.effect))")
        }
        return .restricted
    }

    static func rules(agentsJSON: Data, agent: String) -> [Rule]? {
        (try? JSONDecoder().decode([Agent].self, from: agentsJSON))?.first { $0.id == agent }?.permissions
    }

    /// OpenCode rule: the last matching rule wins. No match means `ask`. The tests use it to probe sample actions.
    static func effect(of action: String, on resource: String, rules: [Rule]) -> String {
        rules.last { matches($0.action, action) && matches($0.resource, resource) }?.effect ?? "ask"
    }

    /// OpenCode wildcards: `*` is any text, `?` is one character. A pattern that ends in ` *` also matches the bare command.
    static func matches(_ pattern: String, _ text: String) -> Bool {
        if pattern.hasSuffix(" *"), matches(String(pattern.dropLast(2)), text) { return true }
        let pattern = Array(pattern), text = Array(text)
        var p = 0, t = 0, star: Int?, mark = 0
        while t < text.count {
            if p < pattern.count, pattern[p] == "*" {
                star = p; mark = t; p += 1
            } else if p < pattern.count, pattern[p] == "?" || pattern[p] == text[t] {
                p += 1; t += 1
            } else if let last = star {
                p = last + 1; mark += 1; t = mark
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}
