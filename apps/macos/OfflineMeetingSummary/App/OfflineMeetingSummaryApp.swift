import SwiftUI

@main
struct OfflineMeetingSummaryApp: App {
    @State private var model: AppModel

    init() {
        // Before any UI text loads, so the chosen language applies at once.
        AppLanguage.apply()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.phase == .recording {
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarIcon.recordingDot)
                    Text(model.elapsedText).monospacedDigit()
                }
            } else {
                Image(nsImage: MenuBarIcon.image(iconState, phase: model.iconPhase))
            }
        }
        .accessibilityLabel(Text(verbatim: "Minutes"))
        .accessibilityValue(statusText)
    }

    /// Spoken by VoiceOver: what the app is doing now.
    private var statusText: Text {
        switch iconState {
        case _ where model.phase == .recording: Text("Recording")
        case .transcribing: Text("Transcribing")
        case .summarizing: Text("Writing minutes")
        case .done: Text("Minutes ready")
        case .busy: Text("Starting or saving")
        case .idle: Text("Ready")
        }
    }

    private var iconState: MenuBarIcon.State {
        if model.phase != .idle { return .busy }
        if let running = model.transcriptionJobs.first(where: { $0.value.isRunning }) {
            return .transcribing(progress: model.transcriptionProgress[running.key])
        }
        if model.summaryJobs.values.contains(where: \.isRunning) { return .summarizing }
        if model.hasUnseenSummary { return .done }
        return .idle
    }
}

extension JobState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
