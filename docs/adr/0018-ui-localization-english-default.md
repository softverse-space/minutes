# ADR-0018: UI localization – English as default, Slovak as translation

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0012](0012-menu-bar-ui-and-settings.md) (UI texts and Settings)

## Context

All UI texts were in Slovak directly in the code. A person who does not speak Slovak could not use the app. The user wants English, and wants it as the default.

The scope is only the app UI. The templates, the detail levels and the system prompt stay in Slovak. The default summary language stays `sk`.

## Options

1. **English texts in the code, Slovak in a String Catalog** – the standard Apple procedure. Xcode extracts the texts automatically. A missing translation shows English.
2. **Slovak texts in the code, English in a String Catalog** – fewer code changes. The development language would not be English, and the fallback would be Slovak.
3. **A custom dictionary in the code** – independent of the system. It does not work with SwiftUI `LocalizedStringKey` and the Xcode tools.

## Decision

We select option 1.

- The development language of the project is `en` (`developmentLanguage` in `project.yml`).
- The UI texts in the code are in English. The Slovak translation is in `OfflineMeetingSummary/Resources/Localizable.xcstrings`.
- The texts from `Info.plist` (microphone and screen permissions) are translated in `InfoPlist.xcstrings`.
- Settings → General has the **App language** option: English (default), Slovenčina, System language.
- English is the default also on a Mac with a Slovak system. The app writes `AppleLanguages` to its domain at startup.
- A language change applies after a restart. Settings has a button for the restart.
- `OutputLanguage.name(for:)` and `DetailLevel` in OMSCore stay in Slovak, because the prompt uses them. The UI uses localized names from the app.

## Consequences

- Write each new UI text in English. After the build, run `xcstringstool sync` (the procedure is in `app/README.md`) and add the Slovak translation.
- Existing users see English after the update. They enable Slovak in Settings.
- The app stores error messages in `errorMessage` in the language that applied at the time of the error.
- The app stores the engine name in the session metadata (`Interný ASR (…)`) in the UI language.
