import AppKit
import AVFoundation
import Observation
import OMSCore
import SwiftUI

enum RecorderPhase: Equatable {
    case idle, starting, recording, stopping
}

enum PopoverTab: String, CaseIterable, Identifiable {
    case record, sessions
    var id: String { rawValue }
    var title: String { self == .record ? String(localized: "New session") : String(localized: "Sessions") }
}

enum JobState: Equatable {
    case running(String)
    case failed(String)
    case done
    /// The user cancelled the job. The UI says so, so a missing result is not a surprise.
    case cancelled
}

@MainActor
@Observable
final class AppModel {
    static let customTemplateID = "__custom__"
    /// Recording needs room for video and audio; 2 GB is about two hours at default quality.
    static let minimumFreeSpace = 2_000_000_000
    /// Below this the app stops a running recording, so the files can still be closed correctly.
    static let criticalFreeSpace = 300_000_000

    // Sources
    var displays: [DisplayInfo] = []
    var microphones: [MicrophoneInfo] = []
    var selectedDisplayID: CGDirectDisplayID? {
        didSet { if let id = selectedDisplayID { UserDefaults.standard.set(Int(id), forKey: SettingsKey.displayID) } }
    }
    var selectedMicrophoneID: String? {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: SettingsKey.microphoneID) }
    }
    var captureMicrophone: Bool {
        didSet { UserDefaults.standard.set(captureMicrophone, forKey: SettingsKey.captureMicrophone) }
    }
    var captureSystemAudio: Bool {
        didSet { UserDefaults.standard.set(captureSystemAudio, forKey: SettingsKey.captureSystemAudio) }
    }
    var hasScreenPermission = SourceCatalog.hasScreenRecordingPermission
    var microphoneDenied = false

    // Recording
    var phase: RecorderPhase = .idle
    var recordingStartedAt: Date?
    var now = Date()
    /// Done part of a running transcription (0…1). Missing while the progress is not known.
    var transcriptionProgress: [URL: Double] = [:]
    /// A summary finished after the user last opened the popover. The menu bar icon shows a badge.
    var hasUnseenSummary = false
    /// Changes several times per second while a job runs, so the menu bar icon can animate.
    var iconPhase: TimeInterval = 0
    var microphoneLevel: Float = 0
    var systemLevel: Float = 0
    var microphoneMuted = false
    var systemMuted = false
    var errorMessage: String?

    // Sessions
    var tab: PopoverTab = .record
    /// Sessions with everything the UI shows, loaded off the main actor by `refreshSessions()`.
    var sessionItems: [SessionItem] = []
    /// Destructive action that the session detail should confirm when it opens.
    var pendingSessionAction: SessionAction?
    var sessionsSize: Int64 { sessionItems.reduce(0) { $0 + $1.size } }
    var focusedSession: SessionFolder? {
        // Each session starts with the default model, so a cloud model is never carried over by mistake.
        didSet { if focusedSession != oldValue { formModelID = Self.defaultModelChoice.id } }
    }
    var transcriptionJobs: [URL: JobState] = [:]
    var summaryJobs: [URL: JobState] = [:]
    /// Jobs that got a cancel and did not stop yet. A model load or a process stop can take some seconds.
    var cancelling: Set<JobKey> = []
    /// The one operation that may use each session now (ADR-0023). Every start of work goes through it.
    private var operations = SessionOperations()

    // Summary form
    var templates: [SummaryTemplate] = []
    var formTemplateID: String
    var formDetail: DetailLevel
    var formLanguage: String
    var formCustomInstruction = ""
    var formExtra = ""
    var formModelID = AppModel.defaultModelChoice.id
    /// Models each engine offers, loaded by `refreshModels()`.
    var engineModels: [SummaryEngine: [EngineModel]] = [:]

    @ObservationIgnored private var recorder: ScreenRecorder?
    @ObservationIgnored private var activeSession: SessionFolder?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var iconTicker: Timer?
    @ObservationIgnored private var tasks: [JobKey: Task<Void, Never>] = [:]
    /// The last queued transcription. WhisperKit holds one model; transcriptions run one after another.
    @ObservationIgnored private var transcriptionQueue: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Identifies the queued transcription of each session. A cancelled waiting job loses its token,
    /// so its task does nothing when its turn comes.
    @ObservationIgnored private var transcriptionTokens: [URL: UUID] = [:]
    /// The session whose transcription runs now. The other queued sessions only wait.
    @ObservationIgnored private var activeTranscription: URL?
    /// The recorder between `start()` and the `.recording` phase, with an error that it reported in that time.
    @ObservationIgnored private var startingRecorder: ScreenRecorder?
    @ObservationIgnored private var pendingStreamError: Error?

    init() {
        AppSettings.registerDefaults()
        let defaults = UserDefaults.standard
        captureMicrophone = defaults.bool(forKey: SettingsKey.captureMicrophone)
        captureSystemAudio = defaults.bool(forKey: SettingsKey.captureSystemAudio)
        selectedMicrophoneID = defaults.string(forKey: SettingsKey.microphoneID)
        let storedDisplay = defaults.integer(forKey: SettingsKey.displayID)
        selectedDisplayID = storedDisplay > 0 ? CGDirectDisplayID(storedDisplay) : nil
        formTemplateID = defaults.string(forKey: SettingsKey.defaultTemplate) ?? "standard"
        formDetail = DetailLevel(rawValue: defaults.string(forKey: SettingsKey.defaultDetail) ?? "") ?? .medium
        formLanguage = defaults.string(forKey: SettingsKey.defaultLanguage) ?? "sk"

        let settings = AppSettings.current
        BundledResources.install(customTemplatesFolder: settings.customTemplatesFolder)
        reloadTemplates()
        Notifier.shared.setUp()
        Task { [weak self] in
            _ = await Task.detached(priority: .utility) {
                SessionLibrary.removeOldVideos(in: settings.sessionsFolder, olderThanDays: settings.videoRetentionDays)
            }.value
            self?.refreshSessions()
        }
    }

    // MARK: Derived state

    var isRecording: Bool { phase == .recording }

    var elapsedText: String {
        guard let start = recordingStartedAt else { return "00:00:00" }
        return Timecode.format(now.timeIntervalSince(start))
    }

    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selectedDisplayID } }

    var canStart: Bool {
        phase == .idle && hasScreenPermission && selectedDisplay != nil
    }

    func template(id: String) -> SummaryTemplate? { templates.first { $0.id == id } }

    // MARK: Sources

    func refreshSources() async {
        hasScreenPermission = SourceCatalog.hasScreenRecordingPermission
        microphoneDenied = [.denied, .restricted].contains(SourceCatalog.microphoneAuthorization)
        microphones = SourceCatalog.microphones()
        if selectedMicrophoneID == nil || !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = SourceCatalog.defaultMicrophoneID ?? microphones.first?.id
        }
        guard hasScreenPermission, phase == .idle else { return }
        do {
            displays = try await SourceCatalog.displays(withThumbnails: true)
            if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displays.first { $0.id == CGMainDisplayID() }?.id ?? displays.first?.id
            }
        } catch {
            errorMessage = String(localized: "Cannot load screens: \(error.localizedDescription)")
        }
    }

    func requestScreenPermission() {
        SourceCatalog.requestScreenRecordingPermission()
        hasScreenPermission = SourceCatalog.hasScreenRecordingPermission
        if !hasScreenPermission { SourceCatalog.openScreenRecordingSettings() }
    }

    // MARK: Recording

    func startSession() async {
        guard phase == .idle, let display = selectedDisplay else { return }
        errorMessage = nil
        phase = .starting

        if captureMicrophone, SourceCatalog.microphoneAuthorization == .notDetermined {
            _ = await SourceCatalog.requestMicrophonePermission()
        }
        let microphoneAllowed = SourceCatalog.microphoneAuthorization == .authorized
        microphoneDenied = captureMicrophone && !microphoneAllowed

        let settings = AppSettings.current
        var startedSession: SessionFolder?
        do {
            try checkDiskSpace(at: settings.sessionsFolder)
            let startedAt = Date()
            let session = SessionFolder(url: settings.sessionsFolder.appending(path: SessionNaming.timestamp(startedAt)))
            try session.createDirectories()
            // The folder is new, so no other operation can hold it.
            _ = operations.begin(.recording, for: session.url)
            startedSession = session
            var metadata = SessionMetadata(startedAt: startedAt)
            metadata.displayName = display.name
            metadata.microphoneName = captureMicrophone && microphoneAllowed
                ? microphones.first { $0.id == selectedMicrophoneID }?.name : nil
            metadata.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            try session.save(metadata)

            let recorder = ScreenRecorder()
            recorder.onStreamError = { [weak self, weak recorder] error in
                Task { @MainActor [weak self] in self?.handleStreamError(error, from: recorder) }
            }
            startingRecorder = recorder
            pendingStreamError = nil
            try await recorder.start(RecordingConfiguration(
                displayID: display.id,
                captureSystemAudio: captureSystemAudio,
                captureMicrophone: captureMicrophone && microphoneAllowed,
                microphoneID: selectedMicrophoneID,
                fps: settings.videoFPS,
                maxWidth: settings.videoMaxWidth,
                videoURL: session.videoURL,
                systemAudioURL: session.audioDirectory.appending(path: "system.m4a"),
                microphoneURL: session.audioDirectory.appending(path: "mic.m4a")
            ))

            self.recorder = recorder
            startingRecorder = nil
            activeSession = session
            microphoneMuted = false
            systemMuted = false
            recordingStartedAt = startedAt
            now = startedAt
            phase = .recording
            startTicker()
            // The recorder reports an error only once. One that came during the start must not be lost.
            if let error = pendingStreamError {
                pendingStreamError = nil
                handleStreamError(error, from: recorder)
            }
        } catch {
            phase = .idle
            recorder = nil
            startingRecorder = nil
            pendingStreamError = nil
            if let startedSession { operations.end(.recording, for: startedSession.url) }
            errorMessage = String(localized: "Recording did not start: \(error.localizedDescription)")
            if !SourceCatalog.hasScreenRecordingPermission { hasScreenPermission = false }
        }
    }

    func stopSession() async {
        guard phase == .recording, let recorder, let session = activeSession else { return }
        phase = .stopping
        stopTicker()

        let result = await recorder.stop()
        var audioTracks: [AudioTrackInfo] = []
        if let system = result.systemAudio {
            audioTracks.append(AudioTrackInfo(file: "audio/\(system.url.lastPathComponent)", speaker: .others, offset: system.offset))
        }
        if let microphone = result.microphone {
            audioTracks.append(AudioTrackInfo(file: "audio/\(microphone.url.lastPathComponent)", speaker: .me, offset: microphone.offset))
        }
        var failure = result.videoError
        do {
            try session.updateMetadata {
                $0.endedAt = Date()
                $0.video = result.videoURL?.lastPathComponent
                $0.audioTracks = audioTracks
            }
        } catch {
            failure = failure ?? error
        }
        if let failure {
            // A stream error already gave its own message. Keep it.
            errorMessage = errorMessage ?? String(localized: "The recording was not saved completely: \(failure.localizedDescription)")
        }

        self.recorder = nil
        activeSession = nil
        recordingStartedAt = nil
        phase = .idle
        operations.end(.recording, for: session.url)

        refreshSessions()
        focusedSession = session
        tab = .sessions
        if audioTracks.isEmpty {
            errorMessage = (errorMessage ?? "") + " " + String(localized: "The recording has no audio, so transcription is not possible.")
        } else if AppSettings.current.autoTranscribe {
            transcribe(session)
        }
    }

    func setMuted(_ muted: Bool, microphone: Bool) {
        if microphone { microphoneMuted = muted } else { systemMuted = muted }
        recorder?.setMuted(muted, microphone: microphone)
        if let start = recordingStartedAt, let session = activeSession {
            let event = SourceEvent(at: Date().timeIntervalSince(start), source: microphone ? "microphone" : "system", enabled: !muted)
            _ = try? session.updateMetadata { $0.sourceEvents.append(event) }
        }
    }

    private func handleStreamError(_ error: Error, from source: ScreenRecorder?) {
        // A late error of an older recorder must not stop the current recording.
        guard let source, source === recorder || source === startingRecorder else { return }
        if phase == .starting {
            pendingStreamError = pendingStreamError ?? error
            return
        }
        guard phase == .recording else { return }
        errorMessage = String(localized: "Recording stopped unexpectedly: \(error.localizedDescription). The saved part stays.")
        Notifier.shared.post(title: String(localized: "Recording stopped unexpectedly"), body: error.localizedDescription)
        Task { await stopSession() }
    }

    /// The check before the start is not enough for a long recording. Runs every few seconds while recording.
    private func checkDiskSpaceWhileRecording() {
        guard phase == .recording, var folder = activeSession?.url else { return }
        folder.removeAllCachedResourceValues()
        guard let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < Self.criticalFreeSpace else { return }
        let message = String(localized: "The disk is almost full, so the app stopped the recording. The saved part stays.")
        errorMessage = message
        Notifier.shared.post(title: String(localized: "Recording stopped unexpectedly"), body: message)
        Task { await stopSession() }
    }

    private func checkDiskSpace(at folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let values = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let free = values.volumeAvailableCapacityForImportantUsage, free < Self.minimumFreeSpace {
            throw RecordingStartError.insufficientDiskSpace
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        // Scheduled on the main run loop, so the callback runs on the main actor.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder else { return }
                self.now = Date()
                self.tickCount += 1
                if self.tickCount.isMultiple(of: 25) { self.checkDiskSpaceWhileRecording() }
                let levels = recorder.levels()
                self.systemLevel = levels.system
                self.microphoneLevel = levels.microphone
            }
        }
    }

    /// Animates the menu bar icon while a transcription or summary runs. Stops by itself.
    private func startIconTicker() {
        guard iconTicker == nil else { return }
        iconTicker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.transcriptionJobs.values.contains(where: \.isRunning) || self.summaryJobs.values.contains(where: \.isRunning) {
                    self.iconPhase = Date().timeIntervalSinceReferenceDate
                } else {
                    self.iconTicker?.invalidate()
                    self.iconTicker = nil
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        microphoneLevel = 0
        systemLevel = 0
    }

    // MARK: Processing

    func transcribe(_ session: SessionFolder) {
        guard operations.begin(.transcription, for: session.url) else { return }
        let key = JobKey(kind: .transcription, session: session.url)
        let previous = transcriptionQueue
        let waiting = transcriptionJobs.contains { $0.key != session.url && $0.value.isRunning }
        transcriptionJobs[session.url] = .running(waiting ? String(localized: "Waiting for another transcription…") : String(localized: "Preparing…"))
        transcriptionProgress[session.url] = nil
        startIconTicker()
        let token = UUID()
        transcriptionTokens[session.url] = token
        let task = Task { [weak self] in
            await previous?.value
            // Cancel released this job while it waited. A newer job of the same session has another token.
            guard self?.transcriptionTokens[session.url] == token else { return }
            self?.activeTranscription = session.url
            await self?.runTranscription(session)
            self?.activeTranscription = nil
            self?.releaseTranscription(session)
        }
        tasks[key] = task
        transcriptionQueue = task
    }

    /// Frees the session after its transcription ended or was cancelled in the queue.
    private func releaseTranscription(_ session: SessionFolder) {
        transcriptionTokens[session.url] = nil
        transcriptionProgress[session.url] = nil
        tasks[JobKey(kind: .transcription, session: session.url)] = nil
        cancelling.remove(JobKey(kind: .transcription, session: session.url))
        operations.end(.transcription, for: session.url)
    }

    private func runTranscription(_ session: SessionFolder) async {
        guard !Task.isCancelled else {
            transcriptionJobs[session.url] = .cancelled
            return
        }
        _ = try? session.updateMetadata { $0.transcription = .running; $0.transcriptionError = nil }
        do {
            // Progress arrives on other threads. Each update checks that the job still runs,
            // so a late message cannot overwrite the final state.
            let transcript = try await TranscriptionService.transcribe(session) { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.transcriptionJobs[session.url]?.isRunning == true,
                          !self.isCancelling(.transcription, session) else { return }
                    self.transcriptionJobs[session.url] = .running(message)
                }
            } fraction: { [weak self] value in
                Task { @MainActor [weak self] in
                    guard self?.transcriptionJobs[session.url]?.isRunning == true else { return }
                    self?.transcriptionProgress[session.url] = value
                }
            }
            _ = try? session.updateMetadata { $0.transcription = .done; $0.transcriptionEngine = transcript.engine }
            transcriptionJobs[session.url] = transcript.isEmpty ? .failed(String(localized: "The transcript contains no speech.")) : .done
            Notifier.shared.post(title: String(localized: "The transcript is done"),
                                 body: String(localized: "\(transcript.segments.count) segments. You can start the summary."),
                                 open: session.transcriptURL("md"))
        } catch is CancellationError {
            _ = try? session.updateMetadata { $0.transcription = .pending }
            transcriptionJobs[session.url] = .cancelled
        } catch {
            _ = try? session.updateMetadata { $0.transcription = .failed; $0.transcriptionError = error.localizedDescription }
            transcriptionJobs[session.url] = .failed(error.localizedDescription)
        }
        refreshSessions()
    }

    func summarize(_ session: SessionFolder) {
        guard operations.begin(.summary, for: session.url) else { return }
        let key = JobKey(kind: .summary, session: session.url)
        let options = SummaryOptions(
            template: formTemplateID == Self.customTemplateID ? nil : template(id: formTemplateID),
            customInstruction: formCustomInstruction,
            detail: formDetail,
            language: formLanguage,
            extraInstruction: formExtra,
            model: formModel
        )
        summaryJobs[session.url] = .running(String(localized: "\(options.model.engine.displayName) is preparing the summary…"))
        startIconTicker()
        tasks[key] = Task { [weak self] in
            do {
                let url = try await SummaryService.summarize(session, options: options)
                self?.summaryJobs[session.url] = .done
                self?.hasUnseenSummary = true
                Notifier.shared.post(title: String(localized: "The summary is done"), body: url.lastPathComponent, open: url)
            } catch is CancellationError {
                self?.summaryJobs[session.url] = .cancelled
            } catch {
                self?.summaryJobs[session.url] = .failed(error.localizedDescription)
            }
            self?.tasks[key] = nil
            self?.cancelling.remove(key)
            self?.operations.end(.summary, for: session.url)
            self?.refreshSessions()
        }
    }

    /// Cancels the jobs of a session. The UI shows "Cancelling…" until the job stops, so a second click is not necessary.
    func cancelJobs(for session: SessionFolder) {
        for kind in JobKey.Kind.allCases {
            let key = JobKey(kind: kind, session: session.url)
            guard let task = tasks[key], !cancelling.contains(key) else { continue }
            cancelling.insert(key)
            task.cancel()
        }
        // A waiting transcription cannot see the cancel before the running one ends. Free the session now.
        if transcriptionTokens[session.url] != nil, activeTranscription != session.url {
            transcriptionJobs[session.url] = .cancelled
            releaseTranscription(session)
        }
    }

    func isCancelling(_ kind: JobKey.Kind, _ session: SessionFolder) -> Bool {
        cancelling.contains(JobKey(kind: kind, session: session.url))
    }

    /// Opens the session detail with a confirmation for a destructive action.
    /// The popover closes when an alert opens, so the confirmation is an inline panel in the detail.
    func confirm(_ action: SessionAction, for session: SessionFolder) {
        focusedSession = session
        pendingSessionAction = action
    }

    /// Cached session details for the UI. Right after a recording stops, the list refresh has not ended yet.
    /// Then the item has no sizes: a recursive size scan must not run on the main actor.
    func item(for session: SessionFolder) -> SessionItem {
        sessionItems.first { $0.session == session } ?? SessionItem(session, measuringStorage: false)
    }

    // MARK: Library

    func reloadTemplates() {
        templates = BundledResources.loadTemplates(customFolder: AppSettings.current.customTemplatesFolder)
        if formTemplateID != Self.customTemplateID, template(id: formTemplateID) == nil {
            formTemplateID = templates.first?.id ?? Self.customTemplateID
        }
    }

    /// Reloads the session list off the main actor. A newer call replaces an older one and stops its scan.
    func refreshSessions() {
        let folder = AppSettings.current.sessionsFolder
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let items = await SessionLibraryLoader.load(in: folder, limit: 500), !Task.isCancelled else { return }
            self?.sessionItems = items
        }
    }

    /// `true` while a recording, a transcription (also a waiting one), a summary or a cleanup uses the session.
    func isBusy(_ session: SessionFolder) -> Bool {
        !operations.isIdle(session.url)
    }

    /// Moves the whole session folder to the Trash.
    func deleteSession(_ session: SessionFolder) {
        guard !isBusy(session) else { return }
        do {
            try session.moveToTrash()
            transcriptionJobs[session.url] = nil
            summaryJobs[session.url] = nil
            if focusedSession == session { focusedSession = nil }
            refreshSessions()
        } catch {
            errorMessage = String(localized: "Cannot delete the session: \(error.localizedDescription)")
        }
    }

    /// Removes video, audio and frames off the main actor. Transcript and outputs stay. Returns the freed bytes.
    @discardableResult
    func cleanUp(_ sessions: [SessionFolder]) async -> Int64 {
        // Each session is held for the whole cleanup, so no transcription or summary can start on it.
        let idle = sessions.filter { operations.begin(.cleanup, for: $0.url) }
        let (freed, failures) = await Task.detached(priority: .userInitiated) { () -> (Int64, [String]) in
            var freed: Int64 = 0
            var failures: [String] = []
            for session in idle where session.hasSourceMedia {
                do { freed += try session.removeSourceMedia() } catch {
                    failures.append(String(localized: "Cannot free up space in \(session.name): \(error.localizedDescription)"))
                }
            }
            return (freed, failures)
        }.value
        for session in idle { operations.end(.cleanup, for: session.url) }
        if let failure = failures.first { errorMessage = failure }
        refreshSessions()
        return freed
    }

    /// Default engine and model for a new summary: OpenCode with the model from Settings.
    static var defaultModelChoice: SummaryModelChoice {
        SummaryModelChoice(engine: .opencode, model: AppSettings.current.opencodeModel)
    }

    var formModel: SummaryModelChoice { SummaryModelChoice(id: formModelID) ?? Self.defaultModelChoice }

    /// Loads model lists of OpenCode and of the cloud engines that are turned on.
    func refreshModels() async {
        let settings = AppSettings.current
        for engine in SummaryEngine.allCases where settings.isEnabled(engine) {
            engineModels[engine] = await SummaryService.listModels(for: engine)
        }
    }

    func applyTemplateDefaults() {
        guard let template = template(id: formTemplateID) else { return }
        if let detail = template.detail { formDetail = detail }
        formLanguage = template.language ?? UserDefaults.standard.string(forKey: SettingsKey.defaultLanguage) ?? "sk"
    }

    func open(_ url: URL) { EditorApp.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    /// Opens the folder itself in Finder (not its parent with the folder selected).
    func openFolder(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// A running job of one kind for one session.
struct JobKey: Hashable {
    enum Kind: CaseIterable { case transcription, summary }
    let kind: Kind
    let session: URL
}

enum RecordingStartError: LocalizedError {
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace: String(localized: "The disk has less than 2 GB of free space.")
        }
    }
}

/// Destructive actions on a session. Both need an explicit confirmation.
enum SessionAction: Equatable {
    case cleanUp, delete
}
