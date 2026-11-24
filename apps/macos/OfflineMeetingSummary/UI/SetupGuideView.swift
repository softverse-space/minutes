import AVFoundation
import OMSCore
import SwiftUI

/// The setup guide at the first launch (ADR-0037). It opens one time by itself.
/// Later the menu of the menu bar icon opens it.
enum SetupGuide {
    static let windowID = "setup-guide"

    /// `true` only at the first launch of a new user. The call marks the guide as shown.
    /// A user of an older version who has a transcription model already does not get the guide.
    @MainActor
    static func takeLaunchTurn() -> Bool {
        let defaults = UserDefaults.standard
        // For a check of the guide: `open Minutes.app --args -showSetupGuide YES`.
        if defaults.bool(forKey: "showSetupGuide") { return true }
        guard !ScreenshotMode.isOn, !defaults.bool(forKey: SettingsKey.setupGuideShown) else { return false }
        defaults.set(true, forKey: SettingsKey.setupGuideShown)
        return !WhisperKitEngine.isDownloaded(AppSettings.current.whisperModel)
    }

    /// A menu bar app is not active by itself, so its new window opens behind other apps.
    @MainActor
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(windowID) == true }
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }
}

struct SetupGuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.asrMode) private var asrMode = AsrMode.local.rawValue
    @AppStorage(SettingsKey.whisperModel) private var whisperModel = AppSettings.defaultWhisperModel
    // Observed here, so the step of the summary updates when a switch changes.
    @AppStorage(SettingsKey.opencodeEnabled) private var opencodeEnabled = true
    @AppStorage(SettingsKey.claudeEnabled) private var claudeEnabled = false
    @AppStorage(SettingsKey.codexEnabled) private var codexEnabled = false
    @State private var microphone = SourceCatalog.microphoneAuthorization
    @State private var downloadProgress: Double?
    @State private var downloadError: String?
    @State private var downloadedTick = 0
    @State private var ffmpegFound = SummaryService.isFfmpegAvailable

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                recordingSection
                transcriptionSection
                summarySection
                optionalSection
            }
            .formStyle(.grouped)
            // The grouped form adds a large top margin under the header.
            .contentMargins(.top, 0, for: .scrollContent)
            Divider()
            HStack {
                Button("Open Settings") {
                    NSApp.activate()
                    openSettings()
                }
                Spacer()
                Button("Start using Minutes") { dismissWindow(id: SetupGuide.windowID) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 680)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Minutes").font(.title2.weight(.semibold))
                Text("Do these steps once. Then you can record a meeting and get the minutes. You can change everything later in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 4)
    }

    // MARK: Steps

    private var recordingSection: some View {
        Section {
            StepRow(number: 1, title: "Screen & System Audio Recording",
                    detail: "The app needs it for the screen and for the sound of the call. After you allow it, restart the app.",
                    done: model.hasScreenPermission) {
                Button("Allow") { model.requestScreenPermission() }
            }
            StepRow(number: 2, title: "Microphone", detail: "The app records your voice from the microphone.",
                    done: microphone == .authorized) {
                Button("Allow") { requestMicrophone() }
            }
        } header: {
            Text("Recording")
        }
    }

    private var transcriptionSection: some View {
        Section {
            if asrMode == AsrMode.local.rawValue {
                let downloaded = downloadedTick >= 0 && WhisperKitEngine.isDownloaded(whisperModel)
                StepRow(number: 3, title: "Transcription model",
                        detail: "The app downloads the model once. Then transcription runs without internet and the audio stays on the Mac.",
                        done: downloaded) {
                    if let downloadProgress {
                        HStack(spacing: 6) {
                            ProgressView(value: downloadProgress).frame(width: 90)
                            Text(downloadProgress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    } else if !downloaded {
                        Button("Download") { download() }
                    }
                }
                Picker("Model", selection: $whisperModel) {
                    ForEach(AppSettings.whisperModels, id: \.id) { Text($0.title).tag($0.id) }
                }
                .disabled(downloadProgress != nil)
                if let downloadError {
                    Text(downloadError).font(.caption).foregroundStyle(.red)
                }
            } else {
                StepRow(number: 3, title: "Transcription model",
                        detail: "The app sends the audio to the transcription server from Settings → Transcription.",
                        done: true) { EmptyView() }
            }
        } header: {
            Text("Transcription")
        }
    }

    private var summarySection: some View {
        Section {
            StepRow(number: 4, title: "Tool for the summary",
                    detail: "Turn on at least one installed tool. The app uses your own login and configuration of the tool.",
                    done: SummaryEngine.allCases.contains { isEnabled($0) && program(for: $0) != nil }) {
                EmptyView()
            }
            ForEach(SummaryEngine.allCases) { engine in
                EngineToggleRow(engine: engine, found: program(for: engine) != nil)
            }
        } header: {
            Text("Summary")
        } footer: {
            Text("Claude and Codex send the transcript to the cloud of their provider. OpenCode with a local model keeps all data on the Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var optionalSection: some View {
        Section {
            LabeledContent {
                StatusLabel(text: ffmpegFound ? "Found" : "Not found (brew install ffmpeg)", ok: ffmpegFound)
            } label: {
                Text(verbatim: "ffmpeg")
                Text("Pictures of the screen in the minutes, and import of more file types.")
            }
        } header: {
            Text("Optional")
        }
    }

    // MARK: Actions

    private func isEnabled(_ engine: SummaryEngine) -> Bool {
        switch engine {
        case .opencode: opencodeEnabled
        case .claude: claudeEnabled
        case .codex: codexEnabled
        }
    }

    private func program(for engine: SummaryEngine) -> String? {
        let path = (UserDefaults.standard.string(forKey: SettingsKey.path(for: engine)) ?? "").expandingTildeInPath
        if !path.isEmpty { return FileManager.default.isExecutableFile(atPath: path) ? path : nil }
        return ProcessRunner.which(engine.executableName)?.path
    }

    private func refresh() {
        microphone = SourceCatalog.microphoneAuthorization
        ffmpegFound = SummaryService.isFfmpegAvailable
        downloadedTick += 1
        Task { await model.refreshSources() }
    }

    private func requestMicrophone() {
        guard microphone == .notDetermined else {
            SourceCatalog.openMicrophoneSettings()
            return
        }
        Task {
            _ = await SourceCatalog.requestMicrophonePermission()
            refresh()
        }
    }

    private func download() {
        downloadError = nil
        downloadProgress = 0
        let model = whisperModel
        Task {
            do {
                try await WhisperKitEngine.shared.download(model) { value in
                    // A late update must not show progress again after the download ended.
                    Task { @MainActor in if downloadProgress != nil { downloadProgress = value } }
                }
                downloadProgress = nil
                downloadedTick += 1
            } catch {
                downloadProgress = nil
                downloadError = String(localized: "Download failed: \(error.localizedDescription)")
            }
        }
    }
}

/// One step: a number or a check mark, the title, a short help text and the action.
private struct StepRow<Action: View>: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let done: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.2))
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(number)").font(.caption.weight(.semibold)).monospacedDigit()
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !done { action() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? Text("Done") : Text("Not done"))
    }
}

/// The switch of one summary tool and whether the app finds its program.
private struct EngineToggleRow: View {
    let engine: SummaryEngine
    let found: Bool
    @AppStorage private var enabled: Bool
    @Environment(AppModel.self) private var model

    init(engine: SummaryEngine, found: Bool) {
        self.engine = engine
        self.found = found
        _enabled = AppStorage(wrappedValue: engine == .opencode, SettingsKey.enabled(for: engine))
    }

    var body: some View {
        Toggle(isOn: $enabled) {
            Text(verbatim: engine.displayName)
            if found {
                Text(engine.cloudVendor.map { String(localized: "Installed. Sends data to \($0).") }
                     ?? String(localized: "Installed. Local or cloud model, as you set it in OpenCode."))
            } else {
                Text("Not installed")
            }
        }
        .onChange(of: enabled) { model.formModelID = AppModel.defaultModelChoice.id }
    }
}
