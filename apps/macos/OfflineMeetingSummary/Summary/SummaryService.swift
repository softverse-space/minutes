import Foundation
import OMSCore

enum SummaryError: LocalizedError {
    case engineNotFound(SummaryEngine)
    case engineDisabled(SummaryEngine)
    case missingSystemPrompt
    case noTranscript
    case emptyInstruction
    case engineFailed(Int32, String)
    case emptyOutput(String)
    case engineLaunchFailed(String)
    case engineTimedOut(minutes: Int)
    case engineOutputTooLarge
    case agentTooBroad(String)
    case agentNotVerified

    var errorDescription: String? {
        switch self {
        case .engineNotFound(let engine):
            String(localized: "\(engine.displayName) was not found. Install it or set its path in Settings → Summary.")
        case .engineDisabled(let engine):
            String(localized: "\(engine.displayName) is turned off. Turn it on in Settings → Summary.")
        case .missingSystemPrompt: String(localized: "The app is missing the system prompt. Install the app again.")
        case .noTranscript: String(localized: "The session has no transcript yet.")
        case .emptyInstruction: String(localized: "Write a custom instruction for the summary you want.")
        case .engineFailed(let code, let stderr): String(localized: "The model stopped with error \(code): \(String(stderr.suffix(400)))")
        case .emptyOutput(let stderr): String(localized: "The model returned no summary. \(String(stderr.suffix(400)))")
        case .engineLaunchFailed(let message): String(localized: "The model did not start: \(message)")
        case .engineTimedOut(let minutes): String(localized: "The model did not finish in \(minutes) minutes. The app stopped it.")
        case .engineOutputTooLarge: String(localized: "The model wrote too much output. The app stopped it.")
        case .agentTooBroad(let action):
            String(localized: "OpenCode gives the summary agent more permissions than the app allows (\(action)). Check your OpenCode version and configuration.")
        case .agentNotVerified:
            String(localized: "The app cannot check the permissions of the OpenCode summary agent, so it did not start the summary. Update OpenCode to version 2 or later and check its configuration.")
        }
    }
}

struct SummaryOptions {
    var template: SummaryTemplate?
    var customInstruction: String
    var detail: DetailLevel
    var language: String
    var extraInstruction: String
    var model: SummaryModelChoice
}

/// Builds the prompt, runs the selected engine and saves the summary in the session folder.
enum SummaryService {
    /// Models an engine offers: `opencode models`, `codex debug models`, or Claude's aliases.
    /// Returns an empty list when the CLI is missing or fails; the picker then offers the default and "Other…".
    static func listModels(for engine: SummaryEngine) async -> [EngineModel] {
        let settings = AppSettings.current
        let command: [String]
        switch engine {
        case .claude: return ClaudeModels.all
        case .opencode: command = ["models"]
        case .codex: command = ["debug", "models"]
        }
        guard let executable = SummaryRunners.executable(for: engine, settings: settings),
              let result = try? await ProcessRunner.run(executable, arguments: command, timeout: .seconds(30)),
              result.exitCode == 0 else { return engine.presetModels }
        switch engine {
        case .opencode: return OpenCodeModels.parse(result.stdout).map { EngineModel(id: $0) }
        case .codex: return CodexModels.parse(Data(result.stdout.utf8))
        case .claude: return ClaudeModels.all
        }
    }

    static var isFfmpegAvailable: Bool { ProcessRunner.which("ffmpeg") != nil }

    /// The frame tool and the `frames` folder, or `nil` when the session has no video or ffmpeg is missing.
    private static func frameAccess(for session: SessionFolder, metadata: SessionMetadata) -> EngineInvocation.FrameAccess? {
        // A session with parts needs the part map; the frame tool finds the video of each part through it (ADR-0029).
        let hasVideo = metadata.hasParts
            ? FileManager.default.fileExists(atPath: session.partsMapURL.path)
                && metadata.parts.contains { FileManager.default.fileExists(atPath: session.partVideoURL($0).path) }
            : FileManager.default.fileExists(atPath: session.videoURL(metadata).path)
        guard hasVideo, isFfmpegAvailable else { return nil }
        return .init(toolPath: BundledResources.installedFrameTool.path, framesPath: session.framesDirectory.path)
    }

    private static func summaryRequest(_ options: SummaryOptions, metadata: SessionMetadata,
                                       frames: EngineInvocation.FrameAccess?) -> SummaryRequest {
        SummaryRequest(
            template: options.template,
            customInstruction: options.customInstruction,
            detail: options.detail,
            language: options.language,
            extraInstruction: options.extraInstruction,
            meetingDate: metadata.startedAt,
            timeZone: TimeZone(identifier: metadata.timeZone) ?? .current,
            frameToolPath: frames?.toolPath,
            partCount: max(1, metadata.parts.count)
        )
    }

    /// Writes the full text that the model gets for these options to a temporary Markdown file and returns it.
    /// The file shows the system prompt and the task. It names the transcript but does not copy it.
    static func previewPrompt(_ session: SessionFolder, options: SummaryOptions) throws -> URL {
        guard let systemPrompt = BundledResources.loadSystemPrompt() else { throw SummaryError.missingSystemPrompt }
        let metadata = try session.loadMetadata()
        let request = summaryRequest(options, metadata: metadata, frames: frameAccess(for: session, metadata: metadata))
        let taskPrompt = PromptBuilder.build(request, details: BundledResources.loadDetailLevels())
        let transcriptURL = session.transcriptURL("md")
        let words = TranscriptionService.hasTranscript(session)
            ? (try? String(contentsOf: transcriptURL, encoding: .utf8)).map(PromptPreview.wordCount)
            : nil
        let text = PromptPreview.render(systemPrompt: systemPrompt, taskPrompt: taskPrompt,
                                        engine: options.model.engine.displayName, model: options.model.model,
                                        transcriptFile: transcriptURL.lastPathComponent, transcriptWords: words)

        let folder = FileManager.default.temporaryDirectory.appending(path: "minutes-prompt-preview")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(session.name)-prompt.md")
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Runs the selected engine and writes `outputs/<date>_meetingsummary_<topic>.md`.
    static func summarize(_ session: SessionFolder, options: SummaryOptions) async throws -> URL {
        let settings = AppSettings.current
        guard TranscriptionService.hasTranscript(session) else { throw SummaryError.noTranscript }
        if options.template == nil, options.customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SummaryError.emptyInstruction
        }

        let metadata = try session.loadMetadata()
        let frames = frameAccess(for: session, metadata: metadata)
        if frames != nil {
            try FileManager.default.createDirectory(at: session.framesDirectory, withIntermediateDirectories: true)
        }
        let request = summaryRequest(options, metadata: metadata, frames: frames)
        let job = SummaryJob(session: session, prompt: PromptBuilder.build(request, details: BundledResources.loadDetailLevels()),
                             model: options.model.model, frames: frames)
        let output = try await SummaryRunners.runner(for: options.model.engine, settings: settings).run(job)

        let (topic, proposedName, body) = SummaryOutput.extract(from: output)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryError.emptyOutput("") }

        try FileManager.default.createDirectory(at: session.outputsDirectory, withIntermediateDirectories: true)
        let existing = Set(session.outputFiles().map(\.lastPathComponent))
        let fallbackTopic = options.template?.id ?? "custom"
        let name = SessionNaming.summaryFileName(date: metadata.startedAt, topic: topic ?? fallbackTopic, existing: existing, proposedName: proposedName)
        let url = session.outputsDirectory.appending(path: name)
        try Data(body.utf8).write(to: url, options: .withoutOverwriting)

        try session.updateMetadata { $0.outputs.append("outputs/\(name)") }
        return url
    }
}
