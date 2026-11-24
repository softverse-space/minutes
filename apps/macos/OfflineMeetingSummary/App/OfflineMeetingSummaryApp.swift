import AppKit
import SwiftUI

/// Stops a running recording correctly before the app quits, also for a restart, a shut down or a
/// log out of the Mac. Without it the files would lose their end (ADR-0030).
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?
    /// The menu of a right click on the menu bar icon (ADR-0033). The app keeps it for its whole run.
    @MainActor static var statusMenu: StatusItemMenu?

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
    @State private var updates: UpdateController

    init() {
        // Before any UI text loads, so the chosen language applies at once.
        AppLanguage.apply()
        let model = AppModel()
        AppDelegate.model = model
        let statusMenu = StatusItemMenu(model: model)
        statusMenu.install()
        AppDelegate.statusMenu = statusMenu
        _model = State(initialValue: model)
        _updates = State(initialValue: UpdateController(hasRunningWork: { [weak model] in model?.hasRunningWork ?? false }))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
                .environment(updates)
        } label: {
            MenuBarLabel()
                .environment(model)
                .environment(updates)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(updates)
        }

        // Setup guide for new users (ADR-0037). The menu bar label opens it at the first launch.
        Window("Welcome to Minutes", id: SetupGuide.windowID) {
            SetupGuideView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(UpdateController.self) private var updates

    var body: some View {
        Group {
            if model.phase == .recording {
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarIcon.recordingDot)
                    Text(model.elapsedText).monospacedDigit()
                }
            } else if iconState == .idle, updates.availableVersion != nil {
                // A new version: a small dot next to the icon. Other states are more important.
                HStack(spacing: 2) {
                    Image(nsImage: MenuBarIcon.image(iconState, phase: model.iconPhase))
                    Image(nsImage: MenuBarIcon.updateDot)
                }
            } else {
                Image(nsImage: MenuBarIcon.image(iconState, phase: model.iconPhase))
            }
        }
        .accessibilityLabel(Text(verbatim: "Minutes"))
        .accessibilityValue(statusText)
        .onAppear {
            let openSettings = openSettings
            AppDelegate.statusMenu?.openSettings = { openSettings() }
            let openWindow = openWindow
            let openGuide = {
                openWindow(id: SetupGuide.windowID)
                SetupGuide.bringToFront()
            }
            AppDelegate.statusMenu?.openSetupGuide = openGuide
            // At launch the app is not active yet. Without the short wait the window stays behind other apps.
            if SetupGuide.takeLaunchTurn() {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    openGuide()
                }
            }
        }
    }

    /// Spoken by VoiceOver: what the app is doing now.
    private var statusText: Text {
        switch iconState {
        case _ where model.phase == .recording: Text("Recording")
        case .transcribing: Text("Transcribing")
        case .summarizing: Text("Writing minutes")
        case .done: Text("Minutes ready")
        case .busy where model.isImporting: Text("Importing")
        case .busy: Text("Starting or saving")
        case .idle where updates.availableVersion != nil: Text("Update available")
        case .idle: Text("Ready")
        }
    }

    private var iconState: MenuBarIcon.State {
        if model.phase != .idle || model.isImporting { return .busy }
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
