import AppKit
import Synchronization
import UserNotifications

/// Local notifications. Clicking a notification opens the attached file.
/// A notification about an interrupted recording has the action "Continue recording" (ADR-0029, flow F5).
final class Notifier: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = Notifier()

    static let interruptedCategory = "recording-interrupted"
    static let continueAction = "continue-recording"

    /// Handlers set once by `setUp`. The delegate calls them on any thread.
    private let handlers = Mutex<(continue: @Sendable (URL) -> Void, show: @Sendable (URL) -> Void)?>(nil)

    /// `onContinue` gets the session folder when the user clicks "Continue recording".
    /// `onShow` gets it when the user clicks the notification itself.
    func setUp(onContinue: @escaping @Sendable (URL) -> Void, onShow: @escaping @Sendable (URL) -> Void) {
        handlers.withLock { $0 = (onContinue, onShow) }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let action = UNNotificationAction(identifier: Self.continueAction, title: String(localized: "Continue recording"),
                                          options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.interruptedCategory, actions: [action], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, open url: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url.path] }
        add(content)
    }

    /// A notification with the action "Continue recording" for `session`.
    func postInterrupted(title: String, body: String, session: URL) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.interruptedCategory
        content.userInfo = ["session": session.path]
        add(content)
    }

    private func add(_ content: UNNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let path = info["session"] as? String {
            let session = URL(filePath: path)
            let handler = handlers.withLock { $0 }
            if response.actionIdentifier == Self.continueAction {
                handler?.continue(session)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                handler?.show(session)
            }
        } else if let path = info["url"] as? String {
            NSWorkspace.shared.open(URL(filePath: path))
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
