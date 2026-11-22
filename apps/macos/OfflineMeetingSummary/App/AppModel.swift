import AppKit
import AVFoundation
import Observation
import OMSCore
import SwiftUI
import UniformTypeIdentifiers

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
    /// `false` records only audio, without a video of the screen (ADR-0032).
    var captureScreen: Bool {
        didSet { UserDefaults.standard.set(captureScreen, forKey: SettingsKey.captureScreen) }
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
    /// The running recording has a video. `false` in the audio-only mode (ADR-0032).
    var recordingCapturesScreen = true
    /// Number of the part that records now, in a session with parts (ADR-0029).
    var activePartNumber: Int?
    /// Recorded time of the earlier parts. The timer shows the time of the whole session.
    var earlierPartsDuration: TimeInterval = 0
    /// `true` until the launch check of interrupted sessions and merges ends. Continue and merge wait for it.
    var isRecovering = true
    /// Sessions whose offer to continue the user closed on the New session tab.
    var dismissedContinueOffers: Set<URL> = []
    var microphoneMuted = false
    var systemMuted = false
    var errorMessage: String?

    // Import (ADR-0034)
    /// Dropped files that wait for the choice: one session or separate sessions.
    var pendingImport: [URL]?
    /// State of the running or the last import. `nil` when there is nothing to show.
    var importJob: JobState?
    /// Done part of the file that the import converts now (0…1). `nil` while it is not known.
    var importProgress: Double?

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
    /// Folder of the part that records now (`parts/02`), or `nil` for a session without parts.
    @ObservationIgnored private var activePart: String?
    @ObservationIgnored private var sessionStoppedForSleep: SessionFolder?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
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
    @ObservationIgnored private var importTask: Task<Void, Never>?

    init() {
        AppSettings.registerDefaults()
        let defaults = UserDefaults.standard
        captureMicrophone = defaults.bool(forKey: SettingsKey.captureMicrophone)
        captureSystemAudio = defaults.bool(forKey: SettingsKey.captureSystemAudio)
        captureScreen = defaults.bool(forKey: SettingsKey.captureScreen)
        selectedMicrophoneID = defaults.string(forKey: SettingsKey.microphoneID)
        let storedDisplay = defaults.integer(forKey: SettingsKey.displayID)
        selectedDisplayID = storedDisplay > 0 ? CGDirectDisplayID(storedDisplay) : nil
        formTemplateID = defaults.string(forKey: SettingsKey.defaultTemplate) ?? "standard"
        formDetail = DetailLevel(rawValue: defaults.string(forKey: SettingsKey.defaultDetail) ?? "") ?? .medium
        formLanguage = defaults.string(forKey: SettingsKey.defaultLanguage) ?? "sk"

        let settings = AppSettings.current
        BundledResources.install(customTemplatesFolder: settings.customTemplatesFolder)
        reloadTemplates()
        Notifier.shared.setUp(onContinue: { [weak self] url in
            Task { @MainActor [weak self] in await self?.continueFromNotification(url) }
        }, onShow: { [weak self] url in
            Task { @MainActor [weak self] in self?.showFromNotification(url) }
        })
        observeSleep()
        let launchedAt = Date()
        Task { [weak self] in
            let (interrupted, failedMerges) = await Task.detached(priority: .utility) {
                await Self.recoverSessions(in: settings.sessionsFolder, before: launchedAt)
            }.value
            _ = await Task.detached(priority: .utility) {
                SessionLibrary.removeOldVideos(in: settings.sessionsFolder, olderThanDays: settings.videoRetentionDays)
            }.value
            guard let self else { return }
            self.isRecovering = false
            if let target = failedMerges.first {
                self.errorMessage = String(localized: "A merge did not finish. No file was deleted. Check the session \(target.name).")
            }
            if let session = interrupted.first {
                Notifier.shared.postInterrupted(title: String(localized: "The last recording was interrupted"),
                                                body: String(localized: "You can continue the same session."), session: session.url)
            }
            self.refreshSessions()
        }
    }

    /// Completes unfinished merges, then repairs sessions without an end (ADR-0029, ADR-0030).
    /// Returns the interrupted sessions, newest first, and the merges that failed again.
    /// Sessions that started after `launchedAt` belong to this app process and stay as they are.
    private nonisolated static func recoverSessions(in folder: URL, before launchedAt: Date) async
        -> (interrupted: [SessionFolder], failedMerges: [SessionFolder]) {
        let failed = SessionMerge.recoverUnfinished(in: folder) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
        // An import that a crash or a quit stopped left only copies in a hidden folder (ADR-0034).
        MediaImport.removeUnfinished(in: folder)
        var interrupted: [SessionFolder] = []
        for session in SessionLibrary.list(in: folder, limit: .max) {
            guard let metadata = try? session.loadMetadata(), metadata.startedAt < launchedAt else { continue }
            let open = metadata.hasParts ? metadata.parts.contains { $0.endedAt == nil } : metadata.endedAt == nil
            guard open || metadata.transcription == .running || metadata.parts.contains(where: { $0.transcription == .running })
                    || (!metadata.hasParts && FileManager.default.fileExists(atPath: session.url.appending(path: "parts/01").path))
            else { continue }
            if (try? await SessionRecovery.recover(session, mediaDuration: MediaProbe.duration)) == true {
                interrupted.append(session)
            }
        }
        return (interrupted, failed)
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        })
    }

    // MARK: Derived state

    var isRecording: Bool { phase == .recording }

    /// Time of the whole session: the earlier parts and the part that records now.
    var elapsedText: String {
        guard let start = recordingStartedAt else { return "00:00:00" }
        return Timecode.format(earlierPartsDuration + now.timeIntervalSince(start))
    }

    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selectedDisplayID } }

    /// The selected sources are enough for a recording: a screen, or in the audio-only mode at least one audio source.
    var hasRecordingSources: Bool {
        captureScreen ? selectedDisplay != nil : (captureSystemAudio || captureMicrophone)
    }

    /// ScreenCaptureKit needs the Screen Recording permission also for system audio, so the audio-only mode needs it too.
    var canStart: Bool {
        phase == .idle && hasScreenPermission && hasRecordingSources
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
        guard hasScreenPermission, phase == .idle, !ScreenshotMode.isOn else { return }
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
        guard phase == .idle, hasRecordingSources else { return }
        let display = captureScreen ? selectedDisplay : nil
        errorMessage = nil
        phase = .starting
        let microphoneAllowed = await prepareMicrophone()

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
            metadata.displayName = display?.name
            metadata.microphoneName = microphoneName(allowed: microphoneAllowed)
            metadata.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            // Known at the start, so a session that a crash interrupts still lists its audio (ADR-0030).
            metadata.audioTracks = plannedTracks(microphoneAllowed: microphoneAllowed)
            try session.save(metadata)
            try await beginRecording(session: session, part: nil, display: display,
                                     microphoneAllowed: microphoneAllowed, startedAt: startedAt)
        } catch {
            failStart(error, session: startedSession, part: nil)
        }
    }

    /// Records a new part into an existing session (ADR-0029, flows F1, F2, F5).
    /// `fromNotification`: the menu bar popover may be closed, so a failure also posts a notification.
    func continueSession(_ session: SessionFolder, fromNotification: Bool = false) async {
        guard phase == .idle, !isRecovering else { return }
        guard hasRecordingSources else {
            let message = captureScreen
                ? String(localized: "Select a screen on the New session tab.")
                : String(localized: "Turn on system audio or the microphone on the New session tab.")
            reportContinueFailure(message, notify: fromNotification)
            return
        }
        let display = captureScreen ? selectedDisplay : nil
        errorMessage = nil
        // The transcription that started after Stop must not block the continue. It runs again after the new part.
        if operations.operation(for: session.url) == .transcription {
            cancelJobs(for: session)
            for _ in 0..<150 where !operations.isIdle(session.url) { try? await Task.sleep(for: .milliseconds(100)) }
        }
        guard phase == .idle, operations.begin(.recording, for: session.url) else {
            reportContinueFailure(String(localized: "The session is busy. Wait until its work ends."), notify: fromNotification)
            return
        }
        phase = .starting
        var partFolder: String?
        do {
            let current = try session.loadMetadata()
            guard current.mediaRemovedAt == nil else { throw ContinueError.mediaRemoved }
            guard !current.isImported else { throw ContinueError.imported }
            guard max(1, current.parts.count) < SessionFolder.maximumParts else { throw SessionPartsError.tooManyParts }
            try checkDiskSpace(at: session.url)
            let microphoneAllowed = await prepareMicrophone()
            let metadata = try session.convertToParts()

            let number = (metadata.parts.compactMap(\.number).max() ?? 0) + 1
            let folder = SessionFolder.partFolderName(number)
            let startedAt = Date()
            var part = SessionPart(folder: folder, startedAt: startedAt, origin: .continued)
            part.displayName = display?.name
            part.microphoneName = microphoneName(allowed: microphoneAllowed)
            part.audioTracks = plannedTracks(microphoneAllowed: microphoneAllowed)
            try FileManager.default.createDirectory(at: session.url.appending(path: "\(folder)/audio"), withIntermediateDirectories: true)
            partFolder = folder
            try session.updateMetadata { $0.parts.append(part) }

            transcriptionJobs[session.url] = nil
            earlierPartsDuration = metadata.duration ?? 0
            dismissedContinueOffers.insert(session.url)
            try await beginRecording(session: session, part: (folder, number), display: display,
                                     microphoneAllowed: microphoneAllowed, startedAt: startedAt)
        } catch {
            failStart(error, session: session, part: partFolder, continuing: true)
            if fromNotification, let message = errorMessage {
                Notifier.shared.post(title: String(localized: "The recording did not continue"), body: message)
            }
        }
    }

    /// Starts the recorder into the session root or into a part folder. The caller holds `.recording`.
    /// `display` is `nil` in the audio-only mode (ADR-0032).
    private func beginRecording(session: SessionFolder, part: (folder: String, number: Int)?, display: DisplayInfo?,
                                microphoneAllowed: Bool, startedAt: Date) async throws {
        let settings = AppSettings.current
        let base = part.map { session.url.appending(path: $0.folder) } ?? session.url
        let recorder = ScreenRecorder()
        recorder.onStreamError = { [weak self, weak recorder] error in
            Task { @MainActor [weak self] in self?.handleStreamError(error, from: recorder) }
        }
        startingRecorder = recorder
        pendingStreamError = nil
        try await recorder.start(RecordingConfiguration(
            displayID: display?.id,
            captureVideo: display != nil,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone && microphoneAllowed,
            microphoneID: selectedMicrophoneID,
            fps: settings.videoFPS,
            maxWidth: settings.videoMaxWidth,
            videoURL: base.appending(path: "recording.mov"),
            systemAudioURL: base.appending(path: "audio/system.m4a"),
            microphoneURL: base.appending(path: "audio/mic.m4a")
        ))

        self.recorder = recorder
        startingRecorder = nil
        activeSession = session
        activePart = part?.folder
        activePartNumber = part?.number
        recordingCapturesScreen = display != nil
        microphoneMuted = false
        systemMuted = false
        recordingStartedAt = startedAt
        now = startedAt
        tickCount = 0
        phase = .recording
        startTicker()
        // The recorder reports an error only once. One that came during the start must not be lost.
        if let error = pendingStreamError {
            pendingStreamError = nil
            handleStreamError(error, from: recorder)
        }
    }

    /// Resets the state after a failed start. A new part that did not start is removed again.
    private func failStart(_ error: Error, session: SessionFolder?, part: String?, continuing: Bool = false) {
        phase = .idle
        recorder = nil
        startingRecorder = nil
        pendingStreamError = nil
        earlierPartsDuration = 0
        if let session {
            if let part {
                _ = try? session.updateMetadata { $0.parts.removeAll { $0.folder == part } }
                try? FileManager.default.removeItem(at: session.url.appending(path: part))
            }
            operations.end(.recording, for: session.url)
        }
        errorMessage = continuing
            ? String(localized: "The recording did not continue: \(Self.message(for: error))")
            : String(localized: "Recording did not start: \(error.localizedDescription)")
        if !SourceCatalog.hasScreenRecordingPermission { hasScreenPermission = false }
    }

    private func reportContinueFailure(_ message: String, notify: Bool) {
        errorMessage = message
        if notify { Notifier.shared.post(title: String(localized: "The recording did not continue"), body: message) }
    }

    private func prepareMicrophone() async -> Bool {
        if captureMicrophone, SourceCatalog.microphoneAuthorization == .notDetermined {
            _ = await SourceCatalog.requestMicrophonePermission()
        }
        let allowed = SourceCatalog.microphoneAuthorization == .authorized
        microphoneDenied = captureMicrophone && !allowed
        return allowed
    }

    private func microphoneName(allowed: Bool) -> String? {
        captureMicrophone && allowed ? microphones.first { $0.id == selectedMicrophoneID }?.name : nil
    }

    /// The audio files that the recorder will write. The offsets come later (heartbeat and Stop).
    private func plannedTracks(microphoneAllowed: Bool) -> [AudioTrackInfo] {
        var tracks: [AudioTrackInfo] = []
        if captureSystemAudio { tracks.append(AudioTrackInfo(file: "audio/system.m4a", speaker: .others, offset: 0)) }
        if captureMicrophone && microphoneAllowed { tracks.append(AudioTrackInfo(file: "audio/mic.m4a", speaker: .me, offset: 0)) }
        return tracks
    }

    /// Stops the recording. `reason` is saved with the recording (ADR-0030).
    /// `autoTranscribe: false` when the app quits or the Mac goes to sleep.
    func stopSession(reason: PartEndReason = .stop, autoTranscribe: Bool = true) async {
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
        let part = activePart
        do {
            let endedAt = Date()
            let metadata = try session.updateMetadata { metadata in
                metadata.endedAt = endedAt
                metadata.interrupted = false
                if let part, let index = metadata.parts.firstIndex(where: { $0.folder == part }) {
                    metadata.parts[index].endedAt = endedAt
                    metadata.parts[index].video = result.videoURL?.lastPathComponent
                    metadata.parts[index].audioTracks = audioTracks
                    metadata.parts[index].endReason = reason
                    metadata.parts[index].interrupted = false
                    metadata.parts[index].lastAliveAt = nil
                    metadata.parts[index].transcription = .pending
                    metadata.transcription = .pending
                } else {
                    metadata.video = result.videoURL?.lastPathComponent
                    metadata.audioTracks = audioTracks
                    metadata.endReason = reason
                    metadata.lastAliveAt = nil
                }
            }
            if metadata.hasParts {
                // The session transcript misses the new part now. `combine` removes it and writes the part map.
                try session.combineTranscripts()
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
        activePart = nil
        activePartNumber = nil
        earlierPartsDuration = 0
        recordingStartedAt = nil
        phase = .idle
        operations.end(.recording, for: session.url)

        refreshSessions()
        focusedSession = session
        tab = .sessions
        if audioTracks.isEmpty {
            errorMessage = (errorMessage ?? "") + " " + String(localized: "The recording has no audio, so transcription is not possible.")
        } else if autoTranscribe, AppSettings.current.autoTranscribe {
            transcribe(session, allParts: false)
        }
    }

    func setMuted(_ muted: Bool, microphone: Bool) {
        if microphone { microphoneMuted = muted } else { systemMuted = muted }
        recorder?.setMuted(muted, microphone: microphone)
        if let start = recordingStartedAt, let session = activeSession {
            let event = SourceEvent(at: Date().timeIntervalSince(start), source: microphone ? "microphone" : "system", enabled: !muted)
            let part = activePart
            _ = try? session.updateMetadata { metadata in
                if let part, let index = metadata.parts.firstIndex(where: { $0.folder == part }) {
                    metadata.parts[index].sourceEvents.append(event)
                } else {
                    metadata.sourceEvents.append(event)
                }
            }
        }
    }

    /// Every 10 seconds while recording: the heartbeat, the audio offsets and `F_FULLFSYNC` (ADR-0030).
    private func heartbeat() {
        guard phase == .recording, let session = activeSession, let recorder else { return }
        let offsets = recorder.trackOffsets()
        let part = activePart
        let now = Date()
        func apply(_ tracks: inout [AudioTrackInfo]) {
            for index in tracks.indices {
                if tracks[index].speaker == .others, let offset = offsets.system { tracks[index].offset = offset }
                if tracks[index].speaker == .me, let offset = offsets.microphone { tracks[index].offset = offset }
            }
        }
        _ = try? session.updateMetadata { metadata in
            if let part, let index = metadata.parts.firstIndex(where: { $0.folder == part }) {
                metadata.parts[index].lastAliveAt = now
                apply(&metadata.parts[index].audioTracks)
            } else {
                metadata.lastAliveAt = now
                apply(&metadata.audioTracks)
            }
        }
        recorder.flushToDisk()
    }

    /// Before the app quits (also for a restart or a shut down of the Mac): stop the recording correctly.
    func stopForTermination() async {
        for _ in 0..<100 where phase == .starting || phase == .stopping {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if phase == .recording { await stopSession(reason: .quit, autoTranscribe: false) }
    }

    private func handleSleep() {
        guard phase == .recording, let session = activeSession else { return }
        sessionStoppedForSleep = session
        Task { await stopSession(reason: .sleep, autoTranscribe: false) }
    }

    private func handleWake() {
        guard let session = sessionStoppedForSleep else { return }
        sessionStoppedForSleep = nil
        Notifier.shared.postInterrupted(title: String(localized: "The recording stopped because the Mac went to sleep"),
                                        body: String(localized: "You can continue the same session."), session: session.url)
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
        if let session = activeSession {
            Notifier.shared.postInterrupted(title: String(localized: "Recording stopped unexpectedly"),
                                            body: error.localizedDescription, session: session.url)
        }
        Task { await stopSession(reason: .streamError) }
    }

    /// The check before the start is not enough for a long recording. Runs every few seconds while recording.
    private func checkDiskSpaceWhileRecording() {
        guard phase == .recording, var folder = activeSession?.url else { return }
        folder.removeAllCachedResourceValues()
        guard let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < Self.criticalFreeSpace else { return }
        let message = String(localized: "The disk is almost full, so the app stopped the recording. The saved part stays.")
        errorMessage = message
        if let session = activeSession {
            Notifier.shared.postInterrupted(title: String(localized: "Recording stopped unexpectedly"), body: message, session: session.url)
        }
        Task { await stopSession(reason: .diskFull) }
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
                if self.tickCount.isMultiple(of: 50) { self.heartbeat() }
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
                if self.transcriptionJobs.values.contains(where: \.isRunning) || self.summaryJobs.values.contains(where: \.isRunning)
                    || self.isImporting {
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

    /// `allParts: false` transcribes only the parts of a session that have no transcript yet (ADR-0029).
    func transcribe(_ session: SessionFolder, allParts: Bool = true) {
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
            await self?.runTranscription(session, allParts: allParts)
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

    private func runTranscription(_ session: SessionFolder, allParts: Bool) async {
        guard !Task.isCancelled else {
            transcriptionJobs[session.url] = .cancelled
            return
        }
        _ = try? session.updateMetadata { $0.transcription = .running; $0.transcriptionError = nil }
        do {
            // Progress arrives on other threads. Each update checks that the job still runs,
            // so a late message cannot overwrite the final state.
            let transcript = try await TranscriptionService.transcribe(session, allParts: allParts) { [weak self] message in
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
            _ = try? session.updateMetadata { metadata in
                metadata.transcription = .pending
                for index in metadata.parts.indices where metadata.parts[index].transcription == .running {
                    metadata.parts[index].transcription = .pending
                }
            }
            transcriptionJobs[session.url] = .cancelled
        } catch {
            let message = Self.message(for: error)
            _ = try? session.updateMetadata { $0.transcription = .failed; $0.transcriptionError = message }
            transcriptionJobs[session.url] = .failed(message)
        }
        refreshSessions()
    }

    /// The summary options from the form in the session detail.
    private var formOptions: SummaryOptions {
        SummaryOptions(
            template: formTemplateID == Self.customTemplateID ? nil : template(id: formTemplateID),
            customInstruction: formCustomInstruction,
            detail: formDetail,
            language: formLanguage,
            extraInstruction: formExtra,
            model: formModel
        )
    }

    /// Opens the full text that the model gets with the current form, in the editor from Settings.
    func previewPrompt(_ session: SessionFolder) {
        do {
            open(try SummaryService.previewPrompt(session, options: formOptions))
        } catch where summaryJobs[session.url]?.isRunning != true {
            summaryJobs[session.url] = .failed(error.localizedDescription)
        } catch {}
    }

    func summarize(_ session: SessionFolder) {
        guard operations.begin(.summary, for: session.url) else { return }
        let key = JobKey(kind: .summary, session: session.url)
        let options = formOptions
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
    func cancelJobs(for session: SessionFolder, kinds: [JobKey.Kind] = JobKey.Kind.allCases) {
        for kind in kinds {
            let key = JobKey(kind: kind, session: session.url)
            guard let task = tasks[key], !cancelling.contains(key) else { continue }
            cancelling.insert(key)
            task.cancel()
        }
        // A waiting transcription cannot see the cancel before the running one ends. Free the session now.
        if kinds.contains(.transcription), transcriptionTokens[session.url] != nil, activeTranscription != session.url {
            transcriptionJobs[session.url] = .cancelled
            releaseTranscription(session)
        }
    }

    /// A transcription runs or waits in the queue.
    var isTranscribing: Bool { transcriptionJobs.values.contains(where: \.isRunning) }
    var isSummarizing: Bool { summaryJobs.values.contains(where: \.isRunning) }

    /// Cancels all transcriptions or all summaries: the running one and the waiting ones.
    func cancelAll(_ kind: JobKey.Kind) {
        let jobs = kind == .transcription ? transcriptionJobs : summaryJobs
        for (url, state) in jobs where state.isRunning {
            cancelJobs(for: SessionFolder(url: url), kinds: [kind])
        }
    }

    /// Starts a recording from the menu of the menu bar icon (ADR-0033). The popover can be closed,
    /// so the sources may not be loaded yet, and a failure also posts a notification.
    func startFromMenu() async {
        guard phase == .idle else { return }
        if displays.isEmpty || microphones.isEmpty { await refreshSources() }
        guard canStart else {
            let message = hasScreenPermission
                ? String(localized: "Open Minutes and select what to record.")
                : String(localized: "The app has no permission to record the screen.")
            Notifier.shared.post(title: String(localized: "Recording did not start"), body: message)
            return
        }
        await startSession()
        if phase == .idle, let message = errorMessage {
            Notifier.shared.post(title: String(localized: "Recording did not start"), body: message)
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

    // MARK: Continue and merge (ADR-0029)

    /// `true` when the session can get a new part now.
    func canContinue(_ item: SessionItem) -> Bool {
        // An imported session has no real time after its end, so a new recording cannot continue it (ADR-0034).
        guard phase == .idle, !isRecovering, let metadata = item.metadata, metadata.mediaRemovedAt == nil,
              !metadata.isImported, metadata.endedAt != nil, max(1, metadata.parts.count) < SessionFolder.maximumParts else { return false }
        let operation = operations.operation(for: item.session.url)
        return operation == nil || operation == .transcription
    }

    /// The offer on the New session tab: the newest session stopped less than 30 minutes ago,
    /// or was interrupted less than 12 hours ago (flow F2).
    var continueOffer: (item: SessionItem, interrupted: Bool)? {
        guard let item = sessionItems.first, !dismissedContinueOffers.contains(item.id), canContinue(item),
              let metadata = item.metadata else { return nil }
        let now = Date()
        if metadata.isInterrupted, now.timeIntervalSince(metadata.startedAt) < 12 * 3600 { return (item, true) }
        if let end = metadata.endedAt, now.timeIntervalSince(end) < 30 * 60 { return (item, false) }
        return nil
    }

    /// Accepts only a session folder in the sessions folder: the path comes from a notification.
    private func validatedSession(_ url: URL) -> SessionFolder? {
        let root = AppSettings.current.sessionsFolder.standardizedFileURL.path
        let session = SessionFolder(url: url.standardizedFileURL)
        guard session.url.deletingLastPathComponent().standardizedFileURL.path == root,
              FileManager.default.fileExists(atPath: session.metadataURL.path) else { return nil }
        return session
    }

    func continueFromNotification(_ url: URL) async {
        guard let session = validatedSession(url) else { return }
        for _ in 0..<100 where isRecovering { try? await Task.sleep(for: .milliseconds(100)) }
        await continueSession(session, fromNotification: true)
    }

    func showFromNotification(_ url: URL) {
        guard phase == .idle, let session = validatedSession(url) else { return }
        tab = .sessions
        focusedSession = session
    }

    /// The next older session in the list: the target of "Merge with previous session".
    func previousSession(of session: SessionFolder) -> SessionItem? {
        guard let index = sessionItems.firstIndex(where: { $0.session == session }), index + 1 < sessionItems.count else { return nil }
        return sessionItems[index + 1]
    }

    /// Why the session cannot merge with the previous session now, or `nil` when it can.
    func mergeProblem(_ item: SessionItem) -> String? {
        guard let previous = previousSession(of: item.session) else { return String(localized: "There is no older session.") }
        guard phase == .idle, !isRecovering, !isBusy(item.session), !isBusy(previous.session) else {
            return String(localized: "The session is busy. Wait until its work ends.")
        }
        guard let target = previous.metadata, let source = item.metadata else { return String(localized: "The session data cannot be read.") }
        do { try SessionMerge.validate(target: target, source: source) } catch { return Self.message(for: error) }
        if (target.mediaRemovedAt != nil && !previous.hasTranscript) || (source.mediaRemovedAt != nil && !item.hasTranscript) {
            return String(localized: "A session without audio and without a transcript cannot be merged.")
        }
        return nil
    }

    func mergeWithPrevious(_ session: SessionFolder) async {
        let item = item(for: session)
        guard mergeProblem(item) == nil, let target = previousSession(of: session)?.session,
              operations.begin(.merge, for: [target.url, session.url]) else { return }
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Bool, Error> in
            Result {
                try SessionMerge.merge(session, into: target) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) } != nil
            }
        }.value
        operations.end(.merge, for: target.url)
        operations.end(.merge, for: session.url)
        transcriptionJobs[session.url] = nil
        summaryJobs[session.url] = nil
        transcriptionJobs[target.url] = nil
        dismissedContinueOffers.remove(target.url)
        switch result {
        case .success(let combined):
            focusedSession = target
            if !combined, AppSettings.current.autoTranscribe, (try? target.loadMetadata())?.hasAudioTracks == true {
                transcribe(target, allParts: false)
            }
        case .failure(let error):
            errorMessage = String(localized: "The sessions were not merged: \(Self.message(for: error))")
        }
        refreshSessions()
    }

    /// A text for the user. OMSCore errors have no localized text of their own.
    static func message(for error: Error) -> String {
        switch error {
        case SessionPartsError.targetExists(let name): String(localized: "The file \(name) already exists in the session.")
        case SessionPartsError.tooManyParts: String(localized: "A session can have at most 99 parts.")
        case SessionPartsError.partNotReady(let number): String(localized: "Part \(number) has no audio and no transcript.")
        case SessionPartsError.overlap: String(localized: "The sessions overlap in time, so you cannot merge them.")
        case SessionPartsError.notEnded: String(localized: "A session that records cannot be merged.")
        case SessionPartsError.sameSession: String(localized: "A session cannot merge with itself.")
        case ContinueError.mediaRemoved: String(localized: "The video and audio of this session are deleted.")
        case ContinueError.imported: String(localized: "An imported session cannot get a new recording.")
        default: error.localizedDescription
        }
    }

    // MARK: Import (ADR-0034)

    var isImporting: Bool { importJob?.isRunning == true }

    /// Opens a file dialog. The popover closes when the dialog opens, so a question about more files is an alert.
    func chooseFilesToImport() {
        guard !isImporting else { return }
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = MediaImport.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.message = String(localized: "Select audio or video files. The app copies them. The original files stay where they are.")
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        requestImport(panel.urls, askInline: false)
    }

    /// Starts an import of `urls`. More than one file needs a choice: one session or separate sessions.
    /// `askInline`: the popover is open (a drop), so the question is a panel on the New session tab.
    func requestImport(_ urls: [URL], askInline: Bool) {
        let files = urls.filter { !$0.hasDirectoryPath }
        let supported = files.filter(MediaImport.isSupported)
        let rejected = files.filter { !MediaImport.isSupported($0) } + urls.filter(\.hasDirectoryPath)
        errorMessage = rejected.isEmpty ? nil : MediaImportError.unsupported(rejected.map(\.lastPathComponent)).localizedDescription
        guard !supported.isEmpty else { return }
        guard !isImporting else {
            errorMessage = MediaImportError.busy.localizedDescription
            return
        }
        guard supported.count > 1 else {
            startImport(supported, asOneSession: false)
            return
        }
        // The panel is on the New session tab. During a recording the popover shows the recording view, so ask with an alert.
        if askInline, phase == .idle {
            focusedSession = nil
            tab = .record
            pendingImport = supported
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Import \(supported.count) files as one session?")
        alert.informativeText = String(localized: "One session makes one transcript and one summary. The files are its parts, in the order of their names.")
        alert.addButton(withTitle: String(localized: "One session"))
        alert.addButton(withTitle: String(localized: "Separate sessions"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: startImport(supported, asOneSession: true)
        case .alertSecondButtonReturn: startImport(supported, asOneSession: false)
        default: break
        }
    }

    /// Imports the files one after another. Each finished session is transcribed at once
    /// when "Transcribe automatically" is on.
    func startImport(_ urls: [URL], asOneSession: Bool) {
        pendingImport = nil
        guard !isImporting, !urls.isEmpty else { return }
        let ordered = MediaImport.ordered(urls)
        let groups = asOneSession ? [ordered] : ordered.map { [$0] }
        let keepVideo = AppSettings.current.importKeepsVideo
        importJob = .running(String(localized: "Preparing the import…"))
        importProgress = nil
        startIconTicker()
        importTask = Task { [weak self] in
            var imported: [SessionFolder] = []
            var failures: [String] = []
            var cancelled = false
            for (index, group) in groups.enumerated() {
                guard let self else { return }
                if Task.isCancelled { cancelled = true; break }
                let counter = groups.count > 1 ? "\(index + 1)/\(groups.count) · " : ""
                do {
                    let session = try await self.importGroup(group, keepVideo: keepVideo, counter: counter)
                    imported.append(session)
                    self.refreshSessions()
                    if AppSettings.current.autoTranscribe { self.transcribe(session) }
                } catch is CancellationError {
                    cancelled = true
                    break
                } catch {
                    failures.append(Self.message(for: error))
                }
            }
            self?.finishImport(imported: imported, failures: failures, cancelled: cancelled)
        }
    }

    func cancelImport() {
        importTask?.cancel()
        if isImporting { importJob = .running(String(localized: "Cancelling…")) }
    }

    private func finishImport(imported: [SessionFolder], failures: [String], cancelled: Bool) {
        importTask = nil
        importProgress = nil
        if let failure = failures.first {
            importJob = .failed(failure)
            Notifier.shared.post(title: String(localized: "The import did not finish"), body: failure)
        } else {
            importJob = cancelled ? .cancelled : nil
        }
        refreshSessions()
        if imported.count == 1, let session = imported.first {
            focusedSession = session
            tab = .sessions
        } else if !imported.isEmpty {
            focusedSession = nil
            tab = .sessions
        }
    }

    /// Imports one group of files into one new session. A group of more files gets one part per file.
    /// The files go to a hidden folder first. Only a complete session gets its real name.
    private func importGroup(_ urls: [URL], keepVideo: Bool, counter: String) async throws -> SessionFolder {
        let root = AppSettings.current.sessionsFolder
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let needed = urls.reduce(Int64(Self.minimumFreeSpace)) { $0 + FileStorage.size(of: $1) }
        if let free = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < needed {
            throw MediaImportError.insufficientDiskSpace
        }

        let startedAt = await MediaImporter.startDate(of: urls[0])
        let name = MediaImport.folderName(startedAt: startedAt, existing: MediaImport.existingNames(in: root))
        let session = SessionFolder(url: root.appending(path: name))
        guard operations.begin(.importing, for: session.url) else { throw MediaImportError.busy }
        defer { operations.end(.importing, for: session.url) }

        let staging = SessionFolder(url: root.appending(path: MediaImport.stagingName(for: name)))
        do {
            try staging.createDirectories()
            var items: [MediaImport.Item] = []
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                let fileCounter = urls.count > 1 ? String(localized: "Part \(index + 1)") + " · " : ""
                importJob = .running(counter + fileCounter + String(localized: "Importing \(url.lastPathComponent)…"))
                importProgress = nil
                let folder = urls.count > 1 ? staging.url.appending(path: SessionFolder.partFolderName(index + 1)) : staging.url
                let result = try await MediaImporter.importFile(url, into: folder, keepVideo: keepVideo) { [weak self] value in
                    Task { @MainActor [weak self] in
                        guard self?.isImporting == true else { return }
                        self?.importProgress = value
                    }
                }
                items.append(MediaImport.Item(fileName: url.lastPathComponent, startedAt: startedAt,
                                              duration: result.duration, video: result.video))
            }
            try Task.checkCancellation()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let metadata = items.count > 1
                ? MediaImport.metadata(forParts: items, appVersion: version)
                : MediaImport.metadata(for: items[0], appVersion: version)
            try staging.save(metadata)
            try staging.writePartsMap(metadata)
            try FileManager.default.moveItem(at: staging.url, to: session.url)
            return session
        } catch {
            try? FileManager.default.removeItem(at: staging.url)
            throw error
        }
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

    /// `true` while any session has an operation, a recording starts or stops, or the launch check runs.
    /// An update does not restart the app at such a time (ADR-0031).
    var hasRunningWork: Bool {
        phase != .idle || isRecovering || !operations.isEmpty || isImporting
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

    /// Default engine and model for a new summary: OpenCode with its default model from Settings.
    /// When OpenCode is off, the first engine that is on, with its default model.
    static var defaultModelChoice: SummaryModelChoice {
        let settings = AppSettings.current
        let engine = SummaryEngine.allCases.first(where: settings.isEnabled) ?? .opencode
        return SummaryModelChoice(engine: engine, model: settings.defaultModel(for: engine))
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

/// Actions on a session that need an explicit confirmation.
enum SessionAction: Equatable {
    case cleanUp, delete, merge
}

enum ContinueError: Error {
    case mediaRemoved
    case imported
}

/// Reads the duration of a media file for the recovery of interrupted sessions (ADR-0030).
enum MediaProbe {
    static let duration: SessionRecovery.MediaDuration = { url in
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let duration = try? await AVURLAsset(url: url).load(.duration), duration.isNumeric, duration.seconds > 0 else { return nil }
        return duration.seconds
    }
}
