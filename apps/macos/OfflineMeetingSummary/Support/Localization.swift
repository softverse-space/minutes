import AppKit
import OMSCore

/// Language of the app UI. English is the default, also on a Mac with another system language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, sk

    static let defaultValue = AppLanguage.en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System language")
        // Language names stay in their own language, so a user can always find them.
        case .en: "English"
        case .sk: "Slovenčina"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: SettingsKey.appLanguage) ?? "") ?? defaultValue
    }

    /// Writes `AppleLanguages` for this app. Call it before the first localized string loads.
    /// A change applies after the app restarts.
    static func apply() {
        let defaults = UserDefaults.standard
        switch current {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case let language: defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}

extension DetailLevel {
    var localizedTitle: String {
        switch self {
        case .brief: String(localized: "Brief")
        case .medium: String(localized: "Medium")
        case .detailed: String(localized: "Detailed")
        }
    }
}

extension OutputLanguage {
    /// Name in the UI language. `name(for:)` is the English name for the prompt.
    static func localizedName(for code: String) -> String {
        switch code {
        case "sk": String(localized: "Slovak")
        case "en": String(localized: "English")
        case "cs": String(localized: "Czech")
        case "de": String(localized: "German")
        default: code
        }
    }
}

enum AppRelauncher {
    /// Starts a new instance of the app and quits this one.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
