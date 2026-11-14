# apps/macos/ – Minutes for macOS

This folder contains the macOS app and its resources.

| Folder | Content | Status |
|---|---|---|
| `scripts/` | Phase 0: a script processes an existing recording | written, not tested on a real recording |
| `templates/` | Template `standard` and the detail levels ([ADR-0007](../../docs/adr/0007-output-templates.md)) | ready |
| `design/` | Icon generator `make-app-icon.py` and previews of the light and dark appearance ([ADR-0020](../../docs/adr/0020-app-icon-light-dark.md)) | done |
| `prompts/` | System prompt `meeting-summary`, independent of the provider. The app copies it to Application Support, where the user can edit it, and makes an OpenCode agent from the copy ([ADR-0015](../../docs/adr/0015-system-prompt-in-app.md), [ADR-0025](../../docs/adr/0025-user-editable-system-prompt.md)) | ready |
| `docs/` | Installation and use | draft |
| `OfflineMeetingSummary/`, `OMSCore/`, `Config/`, `project.yml` | Swift/SwiftUI menu bar app ([ADR-0002](../../docs/adr/0002-native-macos-menu-bar-app.md), [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md), [ADR-0013](../../docs/adr/0013-build-structure-xcodegen.md)) | version 1.0.0 |

## App – build

Requirements: Xcode 26 or later (the app icon is an Icon Composer `.icon` file), `brew install xcodegen`.

```
cd apps/macos
xcodegen generate
xcodebuild -scheme OfflineMeetingSummary -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Minutes.app
```

Logic tests: `cd apps/macos/OMSCore && swift test`.

### Release

`apps/macos/scripts/release.sh` makes the release ([ADR-0021](../../docs/adr/0021-first-release-packaging.md)). The result is `apps/macos/build/release/Minutes-<version>.dmg`.

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Add the changes to [CHANGELOG.md](CHANGELOG.md).
3. Create the notarization profile one time. Enter the app-specific password yourself. Do not save it anywhere:

```
xcrun notarytool store-credentials minutes-notary --apple-id <apple-id> --team-id <TEAM_ID>
```

4. Run the script. For a test build without notarization, use `--skip-notarize`.

```
apps/macos/scripts/release.sh
```

5. Check the `.dmg` on a different Mac: open it, move Minutes to Applications and start it.

### Icon

`design/make-app-icon.py` generates the icon into `OfflineMeetingSummary/Resources/AppIcon.icon` ([ADR-0020](../../docs/adr/0020-app-icon-light-dark.md)). Do not edit the icon manually.

```
python3 apps/macos/design/make-app-icon.py apps/macos/OfflineMeetingSummary/Resources/AppIcon.icon
```

### UI translations

Write the UI texts in the code in English. The Slovak translation is in `OfflineMeetingSummary/Resources/Localizable.xcstrings` ([ADR-0018](../../docs/adr/0018-ui-localization-english-default.md)).

1. Build the app as described above.
2. Add the new texts to the catalog:

```
cd apps/macos
args=(); while IFS= read -r f; do args+=(--stringsdata "$f"); done < <(find build/DerivedData/Build/Intermediates.noindex/OfflineMeetingSummary.build -name '*.stringsdata' ! -name 'ExtractedAppShortcuts*')
xcrun xcstringstool sync OfflineMeetingSummary/Resources/Localizable.xcstrings "${args[@]}"
```

3. Add the Slovak translation in Xcode or directly in the file.

The default signature is ad-hoc. For stable permissions, copy `Config/Signing.xcconfig.example` to `Config/Signing.xcconfig`.

## Phase 0 – quick start

1. Install the tools as described in [docs/install.md](docs/install.md).
2. Record a meeting in OBS.
3. Run:
   ```
   apps/macos/scripts/process-session.sh <video> [template] [detail] [instruction]
   ```

Examples:

```
apps/macos/scripts/process-session.sh ~/Movies/meeting.mov
apps/macos/scripts/process-session.sh ~/Movies/meeting.mov standard strucna
apps/macos/scripts/process-session.sh ~/Movies/meeting.mov standard detailna
apps/macos/scripts/process-session.sh ~/Movies/meeting.mov standard stredna "Focus on the database migration."
```

The result is in `~/Meetings/<timestamp>_<name>/outputs/`.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `OMS_SESSIONS_DIR` | `~/Meetings` | Where the app saves sessions |
| `OMS_ASR` | `local` | `local` (whisper.cpp on the Mac) or `server` (a server with an OpenAI-compatible API; the audio leaves the Mac) |
| `OMS_WHISPER_MODEL` | `~/.local/share/oms/models/ggml-large-v3-turbo.bin` | Model for the local transcript |
| `OMS_LANGUAGE` | `auto` | Speech language: `auto`, `sk`, `cs`, `en` |
| `OMS_ASR_URL` | – | Endpoint `/v1/audio/transcriptions`. Required with `server` |
| `OMS_ASR_MODEL` | – | Model on the server. Required with `server` |
| `OMS_ASR_API_KEY` | – | Key for the transcription server. Set it only in the terminal, not in a file in the repository |
| `OMS_OUTPUT_LANGUAGE` | from the template, else `sk` | Language of the summary |
| `OMS_MODEL` | model from the OpenCode configuration | e.g. `ollama/qwen3:32b` |
