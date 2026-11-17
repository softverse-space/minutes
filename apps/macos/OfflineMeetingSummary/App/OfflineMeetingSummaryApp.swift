import AppKit
import SwiftUI

/// Stops a running recording correctly before the app quits, also for a restart, a shut down or a
/// log out of the Mac. Without it the files would lose their end (ADR-0030).
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.phase != .idle else { return .terminateNow }
        let reply = TerminationReply(sender)
        Task { @MainActor in
            await model.stopForTermination()
            reply.send()
        }
        // The system waits for the reply. Do not wait for ever.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            reply.send()
        }
        return .terminateLater
    }
}

/// Sends the termination reply one time.
@MainActor
private final class TerminationReply {
    private let application: NSApplication
    private var sent = false
    init(_ application: NSApplication) { self.application = application }
    func send() {
        guard !sent else { return }
        sent = true
        application.reply(toApplicationShouldTerminate: true)
    }
}

@main
struct OfflineMeetingSummaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        // Before any UI text loads, so the chosen language applies at once.
        AppLanguage.apply()
        let model = AppModel()
        AppDelegate.model = model
        _model = State(initialValue: model)
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
