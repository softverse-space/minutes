import AppKit
import OMSCore

/// UserDefaults keys and defaults. Views use `@AppStorage` with the same keys.
enum SettingsKey {
    // Recording
    static let sessionsFolder = "sessionsFolder"
    static let videoFPS = "videoFPS"
    static let videoMaxWidth = "videoMaxWidth"
    static let videoRetentionDays = "videoRetentionDays"
    static let captureMicrophone = "captureMicrophone"
    static let captureSystemAudio = "captureSystemAudio"
    /// `false` is the audio-only mode (ADR-0032).
    static let captureScreen = "captureScreen"
    static let microphoneID = "microphoneID"
    static let displayID = "displayID"
    /// An import keeps the video of a video file, so the minutes can use screen frames (ADR-0034).
    static let importKeepsVideo = "importKeepsVideo"
    // Transcription
    static let asrMode = "asrMode"
    static let whisperModel = "whisperModel"
    static let speechLanguage = "speechLanguage"
    static let autoTranscribe = "autoTranscribe"
    static let internalAsrURL = "internalAsrURL"
    static let internalAsrModel = "internalAsrModel"
    // Summary
    static let opencodePath = "opencodePath"
    static let opencodeModel = "opencodeModel"
    static let opencodeAgent = "opencodeAgent"
    static let defaultTemplate = "defaultTemplate"
    static let defaultDetail = "defaultDetail"
    static let defaultLanguage = "defaultLanguage"
    static let customTemplatesFolder = "customTemplatesFolder"
    static let claudeEnabled = "claudeEnabled"
    static let claudePath = "claudePath"
    static let codexEnabled = "codexEnabled"
    static let codexPath = "codexPath"
    static let codexModel = "codexModel"

    /// Opt-in switch of a cloud-only engine. OpenCode has none, it is always on.
    static func enabled(for engine: SummaryEngine) -> String { "\(engine.rawValue)Enabled" }
    /// Default model of an engine. Empty means the engine's own default.
    static func model(for engine: SummaryEngine) -> String { "\(engine.rawValue)Model" }
    /// Configured CLI path of an engine.
    static func path(for engine: SummaryEngine) -> String { "\(engine.rawValue)Path" }
    // General
    static let editorAppPath = "editorAppPath"
    static let appLanguage = "appLanguage"
    // Summary
    /// Digest of the default system prompt that the app wrote to the user's copy last time (ADR-0025).
    static let systemPromptDefaultDigest = "systemPromptDefaultDigest"
}

/// Application that opens transcripts and outputs. Default: Visual Studio Code, if installed.
enum EditorApp {
    static let vsCodeBundleID = "com.microsoft.VSCode"

    static var defaultPath: String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: vsCodeBundleID)?.path ?? ""
    }

    /// Configured app, or `nil` for the system default.
    static var current: URL? {
        let path = UserDefaults.standard.string(forKey: SettingsKey.editorAppPath) ?? ""
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(filePath: path)
    }

    static func displayName(_ path: String) -> String {
        path.isEmpty ? String(localized: "System default app") : FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    static func open(_ url: URL) {
        let textExtensions: Set<String> = ["md", "txt", "srt", "vtt", "json"]
        if let app = current, textExtensions.contains(url.pathExtension.lowercased()) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

enum AsrMode: String, CaseIterable, Identifiable {
    case local
    /// Any server with the OpenAI `/v1/audio/transcriptions` API. The raw value keeps old settings working.
    case server = "internal"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: String(localized: "Locally on the Mac (WhisperKit)")
        case .server: String(localized: "Server (OpenAI-compatible API)")
        }
    }
}

enum AppPaths {
    static var applicationSupport: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OfflineMeetingSummary")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var modelsDirectory: URL { applicationSupport.appending(path: "Models") }
    static var binDirectory: URL { applicationSupport.appending(path: "bin") }
    static var defaultTemplatesFolder: URL { applicationSupport.appending(path: "templates") }
    static var promptsDirectory: URL { applicationSupport.appending(path: "prompts") }
    static var defaultSessionsFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Meetings") }
    static var openCodeAgentDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/opencode/agent")
    }
}

/// A snapshot of current settings for non-UI code.
struct AppSettings {
    var sessionsFolder: URL
    var videoFPS: Int
    var videoMaxWidth: Int
    var videoRetentionDays: Int
    var importKeepsVideo: Bool
    var asrMode: AsrMode
    var whisperModel: String
    var speechLanguage: String
    var autoTranscribe: Bool
    var asrServerURL: String
    var asrServerModel: String
    var opencodePath: String
    var opencodeModel: String
    var opencodeAgent: String
    var customTemplatesFolder: URL
    var claudeEnabled: Bool
    var claudePath: String
    var codexEnabled: Bool
    var codexPath: String
    var codexModel: String
    var claudeModel: String

    /// Default model of an engine from Settings. Empty means the engine's own default.
    func defaultModel(for engine: SummaryEngine) -> String {
        switch engine {
        case .opencode: opencodeModel
        case .claude: claudeModel
        case .codex: codexModel
        }
    }

    /// Configured path of an engine's CLI. Empty means "find it on the search path".
    func executablePath(for engine: SummaryEngine) -> String {
        switch engine {
        case .opencode: opencodePath
        case .claude: claudePath
        case .codex: codexPath
        }
    }

    /// OpenCode is always on. Cloud-only engines need an opt-in, because the transcript leaves the Mac.
    func isEnabled(_ engine: SummaryEngine) -> Bool {
        switch engine {
        case .opencode: true
        case .claude: claudeEnabled
        case .codex: codexEnabled
        }
    }

    static let defaultWhisperModel = "openai_whisper-large-v3-v20240930_turbo"
    static let whisperModels: [(id: String, title: String)] = [
        ("openai_whisper-large-v3-v20240930_turbo", String(localized: "large-v3-turbo (approx. 1.6 GB, best quality)")),
        ("openai_whisper-large-v3-v20240930_turbo_632MB", String(localized: "large-v3-turbo compressed (632 MB)")),
        ("openai_whisper-small", String(localized: "small (quick test, lower quality)")),
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.sessionsFolder: AppPaths.defaultSessionsFolder.path,
            SettingsKey.videoFPS: 5,
            SettingsKey.videoMaxWidth: 1920,
            SettingsKey.videoRetentionDays: 0,
            SettingsKey.captureMicrophone: true,
            SettingsKey.captureSystemAudio: true,
            SettingsKey.captureScreen: true,
            SettingsKey.importKeepsVideo: true,
            SettingsKey.asrMode: AsrMode.local.rawValue,
            SettingsKey.whisperModel: defaultWhisperModel,
            SettingsKey.speechLanguage: "auto",
            SettingsKey.autoTranscribe: true,
            SettingsKey.internalAsrURL: "",
            SettingsKey.internalAsrModel: "",
            SettingsKey.opencodePath: "",
            SettingsKey.opencodeModel: "",
            SettingsKey.opencodeAgent: "meeting-summary",
            SettingsKey.defaultTemplate: "standard",
            SettingsKey.defaultDetail: DetailLevel.medium.rawValue,
            SettingsKey.defaultLanguage: "sk",
            SettingsKey.customTemplatesFolder: AppPaths.defaultTemplatesFolder.path,
            SettingsKey.editorAppPath: EditorApp.defaultPath,
            SettingsKey.claudeEnabled: false,
            SettingsKey.claudePath: "",
            SettingsKey.codexEnabled: false,
            SettingsKey.codexPath: "",
            SettingsKey.codexModel: "",
            SettingsKey.model(for: .claude): "",
        ])
    }

    static var current: AppSettings {
        let d = UserDefaults.standard
        func path(_ key: String) -> URL {
            URL(filePath: (d.string(forKey: key) ?? "").expandingTildeInPath)
        }
        return AppSettings(
            sessionsFolder: path(SettingsKey.sessionsFolder),
            videoFPS: max(1, min(30, d.integer(forKey: SettingsKey.videoFPS))),
            videoMaxWidth: max(640, d.integer(forKey: SettingsKey.videoMaxWidth)),
            videoRetentionDays: max(0, d.integer(forKey: SettingsKey.videoRetentionDays)),
            importKeepsVideo: d.bool(forKey: SettingsKey.importKeepsVideo),
            asrMode: AsrMode(rawValue: d.string(forKey: SettingsKey.asrMode) ?? "") ?? .local,
            whisperModel: d.string(forKey: SettingsKey.whisperModel) ?? defaultWhisperModel,
            speechLanguage: d.string(forKey: SettingsKey.speechLanguage) ?? "auto",
            autoTranscribe: d.bool(forKey: SettingsKey.autoTranscribe),
            asrServerURL: d.string(forKey: SettingsKey.internalAsrURL) ?? "",
            asrServerModel: d.string(forKey: SettingsKey.internalAsrModel) ?? "",
            opencodePath: d.string(forKey: SettingsKey.opencodePath) ?? "",
            opencodeModel: d.string(forKey: SettingsKey.opencodeModel) ?? "",
            opencodeAgent: d.string(forKey: SettingsKey.opencodeAgent) ?? "meeting-summary",
            customTemplatesFolder: path(SettingsKey.customTemplatesFolder),
            claudeEnabled: d.bool(forKey: SettingsKey.claudeEnabled),
            claudePath: d.string(forKey: SettingsKey.claudePath) ?? "",
            codexEnabled: d.bool(forKey: SettingsKey.codexEnabled),
            codexPath: d.string(forKey: SettingsKey.codexPath) ?? "",
            codexModel: d.string(forKey: SettingsKey.codexModel) ?? "",
            claudeModel: d.string(forKey: SettingsKey.model(for: .claude)) ?? ""
        )
    }
}

extension String {
    var expandingTildeInPath: String { (self as NSString).expandingTildeInPath }
}
