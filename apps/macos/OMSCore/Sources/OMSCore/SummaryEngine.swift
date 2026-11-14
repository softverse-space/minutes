import Foundation

/// The command-line tool that writes the summary (ADR-0017, ADR-0022).
public enum SummaryEngine: String, Sendable, CaseIterable, Identifiable {
    /// OpenCode CLI with any provider the user configured: local, self-hosted or cloud.
    case opencode
    /// Claude Code CLI. The transcript goes to Anthropic.
    case claude
    /// OpenAI Codex CLI. The transcript goes to OpenAI.
    case codex

    public var id: String { rawValue }

    /// Product name shown in the UI.
    public var displayName: String {
        switch self {
        case .opencode: "OpenCode"
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Executable name looked up on the search path.
    public var executableName: String { rawValue }

    /// Company that receives the transcript, for cloud-only engines. `nil` for OpenCode,
    /// because its provider depends on the user's configuration.
    public var cloudVendor: String? {
        switch self {
        case .opencode: nil
        case .claude: "Anthropic"
        case .codex: "OpenAI"
        }
    }

    /// Cloud-only engines are off by default and need an explicit opt-in in Settings.
    public var isCloudOnly: Bool { cloudVendor != nil }

    /// Models known without asking the CLI. OpenCode and Codex list theirs at run time.
    public var presetModels: [EngineModel] {
        switch self {
        case .claude: ClaudeModels.all
        case .opencode, .codex: []
        }
    }
}

/// One model an engine can use.
public struct EngineModel: Hashable, Sendable, Identifiable {
    /// Value passed to the CLI (`--model`, `-m`).
    public var id: String
    /// Name shown in pickers.
    public var title: String

    public init(id: String, title: String? = nil) {
        self.id = id
        self.title = title ?? id
    }
}

/// Engine and model for one summary. Stored as `engine:model`, for example `opencode:ollama/qwen3:32b`.
/// An empty model means the engine's own default.
public struct SummaryModelChoice: Hashable, Sendable {
    public var engine: SummaryEngine
    public var model: String

    public init(engine: SummaryEngine, model: String) {
        self.engine = engine
        self.model = model
    }

    public static let openCodeDefault = SummaryModelChoice(engine: .opencode, model: "")

    public var id: String { "\(engine.rawValue):\(model)" }

    /// Parses `id`. Splits at the first colon only, because model names can contain colons.
    public init?(id: String) {
        guard let colon = id.firstIndex(of: ":"),
              let engine = SummaryEngine(rawValue: String(id[..<colon])) else { return nil }
        self.init(engine: engine, model: String(id[id.index(after: colon)...]))
    }
}

public enum OpenCodeModels {
    /// Model ids from the output of `opencode models`: one `provider/model` per line. Other lines are ignored.
    public static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let id = line.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !id.contains(" "), let slash = id.firstIndex(of: "/"),
                  slash != id.startIndex, id.index(after: slash) != id.endIndex,
                  seen.insert(id).inserted else { return nil }
            return id
        }
    }
}

public enum ModelOptions {
    /// Listed models plus configured or selected ids the list does not contain, so a picker always has
    /// a row for its current value. Extra ids come first, in the given order; empty ids are skipped.
    public static func merge(listed: [EngineModel], including extra: [String]) -> [EngineModel] {
        var result = listed
        var known = Set(listed.map(\.id))
        for id in extra.reversed() where !id.isEmpty && known.insert(id).inserted {
            result.insert(EngineModel(id: id), at: 0)
        }
        return result
    }
}

public enum ClaudeModels {
    /// Aliases that Claude Code resolves to the latest model of each family.
    /// Claude has no command that lists models, so other model names are entered as text.
    public static let all: [EngineModel] = [
        EngineModel(id: "sonnet", title: "Claude Sonnet"),
        EngineModel(id: "opus", title: "Claude Opus"),
        EngineModel(id: "haiku", title: "Claude Haiku"),
    ]

    public static func title(for id: String) -> String {
        all.first { $0.id == id }?.title ?? id
    }
}

public enum CodexModels {
    private struct Catalog: Decodable {
        struct Model: Decodable {
            let slug: String
            let display_name: String?
            let visibility: String?
            let priority: Int?
        }
        let models: [Model]
    }

    /// Models from `codex debug models` (JSON). Hidden models are left out, the rest keep Codex's order.
    public static func parse(_ data: Data) -> [EngineModel] {
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return catalog.models
            .filter { ($0.visibility ?? "list") != "hide" }
            .sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
            .map { EngineModel(id: $0.slug, title: $0.display_name ?? $0.slug) }
    }
}
