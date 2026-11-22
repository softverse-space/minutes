import Foundation

/// Debug builds only: `-screenshotMode YES` on the command line prepares the app for the website screenshots.
/// The app then acts as if it had the Screen Recording permission and does not load the screens,
/// so a Debug build can show the New session tab without taking the permission from the installed app.
/// Settings → General and About show the update controls of the released app.
/// Use it with invented sample sessions (`-sessionsFolder`) and `-captureScreen NO`.
enum ScreenshotMode {
    static var isOn: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "screenshotMode")
        #else
        false
        #endif
    }
}
