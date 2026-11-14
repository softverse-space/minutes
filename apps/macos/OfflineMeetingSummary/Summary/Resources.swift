import Foundation
import OMSCore

/// Bundled resources: templates, the system prompt and the frame tool.
enum BundledResources {
    static var templatesDirectory: URL? { Bundle.main.url(forResource: "templates", withExtension: nil) }
    static var promptsDirectory: URL? { Bundle.main.url(forResource: "prompts", withExtension: nil) }
    static var frameTool: URL? { Bundle.main.url(forResource: "frame-at", withExtension: "sh") }

    /// Stable path of the frame tool. The OpenCode agent allows only this exact path (ADR-0023).
    static var installedFrameTool: URL { AppPaths.binDirectory.appending(path: "frame-at.sh") }

    static func loadTemplates(customFolder: URL) -> [SummaryTemplate] {
        TemplateLoader.load(from: [templatesDirectory, customFolder].compactMap { $0 })
    }

    static func loadDetailLevels() -> DetailLevelCatalog {
        guard let url = templatesDirectory?.appending(path: "_detail-levels.md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return DetailLevelCatalog(instructions: [:]) }
        return DetailLevelCatalog.parse(text)
    }

    /// The default system prompt in the app bundle (`prompts/meeting-summary.md`).
    static func loadDefaultSystemPrompt() -> String? {
        guard let url = promptsDirectory?.appending(path: "\(SystemPrompt.name).md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The user's editable copy of the system prompt (ADR-0025).
    static var userSystemPromptFile: URL { AppPaths.promptsDirectory.appending(path: "\(SystemPrompt.name).md") }

    /// The system prompt that the summary uses: the user's copy, or the default (ADR-0025).
    static func loadSystemPrompt() -> String? {
        SystemPrompt.effective(userCopy: try? String(contentsOf: userSystemPromptFile, encoding: .utf8),
                               bundledDefault: loadDefaultSystemPrompt())
    }

    /// `true` when the user's copy differs from the default in the app.
    static var isSystemPromptEdited: Bool {
        guard let copy = try? String(contentsOf: userSystemPromptFile, encoding: .utf8),
              let bundled = loadDefaultSystemPrompt() else { return false }
        return SystemPrompt.effective(userCopy: copy, bundledDefault: bundled) != bundled
    }

    /// Creates the user's copy. Replaces it with a new default only when the user did not edit it.
    static func installUserSystemPrompt() {
        guard let bundled = loadDefaultSystemPrompt() else { return }
        let copy = try? String(contentsOf: userSystemPromptFile, encoding: .utf8)
        let lastDigest = UserDefaults.standard.string(forKey: SettingsKey.systemPromptDefaultDigest)
        if SystemPrompt.copyAction(userCopy: copy, bundledDefault: bundled, lastWrittenDefaultDigest: lastDigest) == .writeDefault {
            try? writeUserSystemPrompt(bundled)
        } else if copy == bundled {
            UserDefaults.standard.set(SystemPrompt.digest(bundled), forKey: SettingsKey.systemPromptDefaultDigest)
        }
    }

    /// Replaces the user's copy with the default from the app.
    static func resetUserSystemPrompt() throws {
        guard let bundled = loadDefaultSystemPrompt() else { return }
        try writeUserSystemPrompt(bundled)
        try syncOpenCodeAgent()
    }

    private static func writeUserSystemPrompt(_ text: String) throws {
        try FileManager.default.createDirectory(at: AppPaths.promptsDirectory, withIntermediateDirectories: true)
        try text.write(to: userSystemPromptFile, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(SystemPrompt.digest(text), forKey: SettingsKey.systemPromptDefaultDigest)
    }

    /// Copies the frame tool and the system prompt to Application Support, creates the custom templates folder
    /// and syncs the OpenCode agent with the system prompt.
    static func install(customTemplatesFolder: URL) {
        installUserSystemPrompt()
        try? syncOpenCodeAgent()
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: AppPaths.binDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: customTemplatesFolder, withIntermediateDirectories: true)
        if let source = frameTool {
            try? fileManager.removeItem(at: installedFrameTool)
            try? fileManager.copyItem(at: source, to: installedFrameTool)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedFrameTool.path)
        }
    }

    static var openCodeAgentFile: URL {
        AppPaths.openCodeAgentDirectory.appending(path: "\(OpenCodeAgent.managedName).md")
    }

    /// `true` when the installed OpenCode agent matches the system prompt.
    static var isAgentInSync: Bool {
        guard let prompt = loadSystemPrompt() else { return false }
        let installed = try? String(contentsOf: openCodeAgentFile, encoding: .utf8)
        return !OpenCodeAgent.needsSync(installed: installed, systemPrompt: prompt, frameToolPath: installedFrameTool.path)
    }

    /// Writes `~/.config/opencode/agent/meeting-summary.md` from the system prompt when it differs.
    /// The app owns this file. Manual changes in it are overwritten.
    static func syncOpenCodeAgent() throws {
        guard let prompt = loadSystemPrompt() else { return }
        let installed = try? String(contentsOf: openCodeAgentFile, encoding: .utf8)
        let frameTool = installedFrameTool.path
        guard OpenCodeAgent.needsSync(installed: installed, systemPrompt: prompt, frameToolPath: frameTool) else { return }
        try FileManager.default.createDirectory(at: AppPaths.openCodeAgentDirectory, withIntermediateDirectories: true)
        try OpenCodeAgent.render(systemPrompt: prompt, frameToolPath: frameTool)
            .write(to: openCodeAgentFile, atomically: true, encoding: .utf8)
    }
}
