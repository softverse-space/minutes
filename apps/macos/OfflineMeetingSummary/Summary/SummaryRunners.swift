import Foundation
import OMSCore

/// Everything a summary engine needs for one run.
struct SummaryJob {
    let session: SessionFolder
    /// Task prompt built by `PromptBuilder`: template, detail level, language and frame rules.
    let prompt: String
    /// Engine-specific model id. Empty means the engine's own default.
    let model: String
    /// The frame tool and the `frames` folder, or `nil` when the session has no video or ffmpeg is missing.
    let frames: EngineInvocation.FrameAccess?
}

/// Runs one summary engine and returns the model's text output.
/// One type per engine keeps `SummaryService` closed for modification when an engine is added.
protocol SummaryRunner {
    var engine: SummaryEngine { get }
    func run(_ job: SummaryJob) async throws -> String
}

enum SummaryRunners {
    static func runner(for engine: SummaryEngine, settings: AppSettings) -> SummaryRunner {
        switch engine {
        case .opencode: OpenCodeRunner(settings: settings)
        case .claude: ClaudeRunner(settings: settings)
        case .codex: CodexRunner(settings: settings)
        }
    }

    /// The configured path if it is set, otherwise the executable from the search path.
    static func executable(for engine: SummaryEngine, settings: AppSettings) -> URL? {
        let configured = settings.executablePath(for: engine).trimmingCharacters(in: .whitespaces).expandingTildeInPath
        if !configured.isEmpty {
            return FileManager.default.isExecutableFile(atPath: configured) ? URL(filePath: configured) : nil
        }
        return ProcessRunner.which(engine.executableName)
    }

    /// Task prompt and transcript for engines that read stdin (Claude, Codex).
    /// OpenCode gets the transcript as an attached file and the system prompt as its agent (ADR-0015).
    static func standaloneInput(for job: SummaryJob) throws -> String {
        let transcript = try String(contentsOf: job.session.transcriptURL("md"), encoding: .utf8)
        return "\(job.prompt)\n\n## Meeting transcript\n\n\(transcript)"
    }

    /// A summary of a long meeting with a local model can take long. The limit only stops a process that hangs.
    static let timeout: Duration = .seconds(2 * 60 * 60)

    /// Runs an engine in the session folder and turns runner errors into errors with a text for the user.
    fileprivate static func launch(_ executable: URL, arguments: [String], job: SummaryJob, input: Data? = nil,
                                   stdout: OutputCapture = .limited(bytes: ProcessRunner.defaultStdoutLimit)) async throws -> ProcessResult {
        do {
            return try await ProcessRunner.run(executable, arguments: arguments, currentDirectory: job.session.url,
                                               input: input, timeout: timeout, stdout: stdout)
        } catch ProcessRunnerError.launchFailed(let message) {
            throw SummaryError.engineLaunchFailed(message)
        } catch ProcessRunnerError.timedOut(let seconds) {
            throw SummaryError.engineTimedOut(minutes: seconds / 60)
        } catch ProcessRunnerError.outputTooLarge {
            throw SummaryError.engineOutputTooLarge
        }
    }

    fileprivate static func check(_ result: ProcessResult) throws -> String {
        guard result.exitCode == 0 else { throw SummaryError.engineFailed(result.exitCode, result.stderr) }
        return result.stdout
    }

    fileprivate static func requireEnabledEngine(_ engine: SummaryEngine, settings: AppSettings) throws {
        guard settings.isEnabled(engine) else { throw SummaryError.engineDisabled(engine) }
    }
}

/// `opencode run` with the managed agent. The transcript is an attached file.
struct OpenCodeRunner: SummaryRunner {
    let settings: AppSettings
    var engine: SummaryEngine { .opencode }

    func run(_ job: SummaryJob) async throws -> String {
        try SummaryRunners.requireEnabledEngine(engine, settings: settings)
        guard let opencode = SummaryRunners.executable(for: engine, settings: settings) else {
            throw SummaryError.engineNotFound(engine)
        }
        try BundledResources.syncOpenCodeAgent()
        try await requireRestrictedAgent(opencode, job: job)
        let arguments = EngineInvocation.openCode(agent: OpenCodeAgent.managedName, title: "Meeting \(job.session.name)",
                                                  transcriptPath: job.session.transcriptURL("md").path,
                                                  model: job.model, prompt: job.prompt)
        let result = try await SummaryRunners.launch(opencode, arguments: arguments, job: job)
        return try SummaryRunners.check(result)
    }

    /// Asks OpenCode which permissions it gives the managed agent. The summary starts only when the check
    /// succeeds and the permissions are narrow (ADR-0023). The agent file is only a request: the OpenCode
    /// version and the user's configuration decide the result. A failed or unreadable check is a refusal,
    /// so OpenCode 1.x, which has no such list, cannot run the managed agent.
    private func requireRestrictedAgent(_ opencode: URL, job: SummaryJob) async throws {
        let listing: ProcessResult
        do {
            listing = try await ProcessRunner.run(opencode, arguments: ["debug", "agents"], currentDirectory: job.session.url,
                                                  timeout: .seconds(30))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SummaryError.agentNotVerified
        }
        guard listing.exitCode == 0 else { throw SummaryError.agentNotVerified }
        switch OpenCodePolicy.check(agentsJSON: Data(listing.stdout.utf8), agent: OpenCodeAgent.managedName,
                                    frameToolPath: BundledResources.installedFrameTool.path) {
        case .restricted: return
        case .tooBroad(let rule): throw SummaryError.agentTooBroad(rule)
        case .unknown: throw SummaryError.agentNotVerified
        }
    }
}

/// `claude -p` with the app's system prompt. Prompt and transcript go through stdin.
/// Tools: none, or Read plus Bash restricted to `frame-at.sh` when frames are available (ADR-0023).
struct ClaudeRunner: SummaryRunner {
    let settings: AppSettings
    var engine: SummaryEngine { .claude }

    func run(_ job: SummaryJob) async throws -> String {
        try SummaryRunners.requireEnabledEngine(engine, settings: settings)
        guard let claude = SummaryRunners.executable(for: engine, settings: settings) else {
            throw SummaryError.engineNotFound(engine)
        }
        guard let systemPrompt = BundledResources.loadSystemPrompt() else { throw SummaryError.missingSystemPrompt }

        let arguments = EngineInvocation.claude(systemPrompt: systemPrompt, model: job.model, frames: job.frames)
        let input = try SummaryRunners.standaloneInput(for: job)
        let result = try await SummaryRunners.launch(claude, arguments: arguments, job: job, input: Data(input.utf8))
        return try SummaryRunners.check(result)
    }
}

/// `codex exec` in its sandbox. The system prompt, task and transcript go through stdin,
/// and Codex writes its final answer to a file, because stdout carries progress events.
/// The sandbox is read-only, or workspace-write limited to the `frames` folder when the model may cut frames.
struct CodexRunner: SummaryRunner {
    let settings: AppSettings
    var engine: SummaryEngine { .codex }

    func run(_ job: SummaryJob) async throws -> String {
        try SummaryRunners.requireEnabledEngine(engine, settings: settings)
        guard let codex = SummaryRunners.executable(for: engine, settings: settings) else {
            throw SummaryError.engineNotFound(engine)
        }
        guard let systemPrompt = BundledResources.loadSystemPrompt() else { throw SummaryError.missingSystemPrompt }

        let answer = FileManager.default.temporaryDirectory.appending(path: "minutes-codex-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: answer) }

        let arguments = EngineInvocation.codex(sessionPath: job.session.url.path, framesPath: job.frames?.framesPath,
                                               answerPath: answer.path, model: job.model)

        // Codex has no system prompt flag, so the shared rules come first in the input.
        let input = "\(systemPrompt)\n\n" + (try SummaryRunners.standaloneInput(for: job))
        // stdout carries progress events, not the answer, so only its end is kept.
        let result = try await SummaryRunners.launch(codex, arguments: arguments, job: job, input: Data(input.utf8),
                                                     stdout: .tail(bytes: ProcessRunner.stderrTailBytes))
        _ = try SummaryRunners.check(result)
        return (try? String(contentsOf: answer, encoding: .utf8)) ?? ""
    }
}
