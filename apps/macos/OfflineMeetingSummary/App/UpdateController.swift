import AppKit
import Sparkle

/// Checks for and installs app updates with Sparkle (ADR-0031, docs/specs/app-updates.md).
///
/// - Scheduled updates show as gentle reminders: a dot on the menu bar icon and a row in the popover.
///   Sparkle opens its window only when the user clicks.
/// - While a job runs, the app does not restart for an update. The install waits for the end of the work.
/// - A build without a feed URL or a public key (for example the Debug build) never checks for updates.
@MainActor
@Observable
final class UpdateController: NSObject {
    /// The version that a scheduled check found and that the user did not look at yet.
    private(set) var availableVersion: String?
    /// `true` when a downloaded update waits for the end of a job before the app restarts.
    private(set) var isWaitingForIdle = false
    private(set) var canCheckForUpdates = false

    /// `true` when this build can update itself.
    let isEnabled: Bool

    var automaticallyChecks: Bool {
        get { access(keyPath: \.automaticallyChecks); return controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            withMutation(keyPath: \.automaticallyChecks) { controller?.updater.automaticallyChecksForUpdates = newValue }
            // Without automatic checks there is nothing to download automatically.
            if !newValue { automaticallyDownloads = false }
        }
    }

    var automaticallyDownloads: Bool {
        get { access(keyPath: \.automaticallyDownloads); return controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { withMutation(keyPath: \.automaticallyDownloads) { controller?.updater.automaticallyDownloadsUpdates = newValue } }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var pendingInstall: (() -> Void)?
    @ObservationIgnored private var idleWatch: Task<Void, Never>?
    @ObservationIgnored private let hasRunningWork: @MainActor () -> Bool

    /// `hasRunningWork` tells if a recording or a job runs now.
    init(hasRunningWork: @escaping @MainActor () -> Bool, bundle: Bundle = .main) {
        self.hasRunningWork = hasRunningWork
        isEnabled = Self.isConfigured(bundle)
        super.init()
        guard isEnabled else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        // Sparkle changes this property on the main thread.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            MainActor.assumeIsolated { self?.canCheckForUpdates = value }
        }
    }

    /// A feed URL and a public key are both necessary. Sparkle refuses updates without the key.
    static func isConfigured(_ bundle: Bundle) -> Bool {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !feed.trimmingCharacters(in: .whitespaces).isEmpty && !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Shows the Sparkle window: a new version, the update that waits, or "You're up to date".
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// Restarts at once into the update that waits for idle. The caller makes sure that no job runs.
    private func installPendingIfIdle() {
        guard let install = pendingInstall, !hasRunningWork() else { return }
        pendingInstall = nil
        isWaitingForIdle = false
        idleWatch?.cancel()
        idleWatch = nil
        install()
    }

    /// Checks every few seconds if the work ended. A job can take many minutes, so a short poll is cheap.
    private func watchForIdle() {
        idleWatch?.cancel()
        idleWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.pendingInstall != nil else { return }
                self.installPendingIfIdle()
            }
        }
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard hasRunningWork() else { return false }
        pendingInstall = installHandler
        isWaitingForIdle = true
        watchForIdle()
        return true
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // A menu bar app has no window in front. Do not open the Sparkle window at a random time.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated { availableVersion = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
