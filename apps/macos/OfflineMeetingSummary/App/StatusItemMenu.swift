import AppKit

/// The menu that opens on a right click or a Control-click on the menu bar icon (ADR-0033).
/// A left click still opens the popover. SwiftUI `MenuBarExtra` has no API for a second menu,
/// so a local event monitor finds the clicks on the status bar window of the app.
@MainActor
final class StatusItemMenu {
    private let model: AppModel
    private var monitor: Any?
    /// Set by the menu bar label, because only a SwiftUI view can open the Settings window.
    var openSettings: (() -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            // AppKit calls local monitors on the main thread.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated {
                guard let self, Self.isMenuClick(event), let view = event.window?.contentView else { return false }
                self.show(in: view)
                return true
            }
            return handled ? nil : event
        }
    }

    /// The app has one status item: the `MenuBarExtra`. Its window has the private class `NSStatusBarWindow`.
    private static func isMenuClick(_ event: NSEvent) -> Bool {
        guard let window = event.window, String(describing: type(of: window)) == "NSStatusBarWindow" else { return false }
        return event.type == .rightMouseDown || event.modifierFlags.contains(.control)
    }

    private func show(in view: NSView) {
        let button = view as? NSButton ?? view.subviews.lazy.compactMap { $0 as? NSButton }.first
        button?.highlight(true)
        defer { button?.highlight(false) }
        // Below the icon, like the menu of other menu bar items. The call returns when the menu closes.
        let point = NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4)
        makeMenu().popUp(positioning: nil, at: point, in: view)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let model = model

        switch model.phase {
        case .idle:
            menu.addItem(ActionMenuItem(String(localized: "Start recording"), symbol: "record.circle") {
                Task { await model.startFromMenu() }
            })
        case .starting:
            menu.addItem(ActionMenuItem(String(localized: "Starting…"), symbol: "record.circle", enabled: false) {})
        case .recording:
            menu.addItem(ActionMenuItem(String(localized: "Stop recording"), symbol: "stop.fill") {
                Task { await model.stopSession() }
            })
        case .stopping:
            menu.addItem(ActionMenuItem(String(localized: "Saving recording…"), symbol: "stop.fill", enabled: false) {})
        }
        menu.addItem(ActionMenuItem(String(localized: "Stop transcription"), symbol: "waveform.slash",
                                    enabled: model.isTranscribing) { model.cancelAll(.transcription) })
        menu.addItem(ActionMenuItem(String(localized: "Stop writing minutes"), symbol: "xmark.circle",
                                    enabled: model.isSummarizing) { model.cancelAll(.summary) })

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "Settings…"), symbol: "gearshape", key: ",") { [weak self] in
            NSApp.activate()
            self?.openSettings?()
        })
        menu.addItem(.separator())
        // A running recording stops correctly before the app quits (ADR-0030).
        menu.addItem(ActionMenuItem(String(localized: "Quit Minutes"), key: "q") { NSApp.terminate(nil) })
        return menu
    }
}

/// A menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        isEnabled = enabled
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
