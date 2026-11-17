# Specification: app updates

- **Status:** Draft, not implemented
- **Date:** 2026-11-17
- **Decision:** [ADR-0031](../adr/0031-app-updates-sparkle.md) (proposed)
- **Amends:** [ADR-0011](../adr/0011-distribution-signed-dmg.md) and [ADR-0021](../adr/0021-first-release-packaging.md) ("updates are manual")

## 1. Problem

The app does not know that a new version exists. The user must check the GitHub releases page, download a new `.dmg` and replace the app manually. Most users stay on an old version.

## 2. Goals and non-goals

**Goals**
1. The app tells the user that a new version exists.
2. The user installs the new version with one click. The app restarts in the new version.
3. The update never interrupts a recording, a transcription or a summary.
4. The update keeps the Screen Recording and Microphone permissions, the settings, the data and the Keychain.
5. The app installs only an update that the author signed. A changed file on GitHub or on the network is rejected.
6. The app sends no telemetry. The check sends only a normal HTTPS request for one public file.

**Non-goals (this version)**
- Delta updates.
- A beta channel. (The design allows it later, see section 9.)
- Forced updates and a minimum supported version.
- Updates through the Mac App Store.

## 3. Options

| # | Option | Notify | Install | Work | Risk |
|---|---|---|---|---|---|
| A | Check the GitHub API (`/repos/softverse-space/minutes/releases/latest`), compare the version, open the release page | Yes | No, manual `.dmg` | Small, no dependency | GitHub API rate limit (60 requests per hour per IP). No signature check, because the app installs nothing |
| B | **Sparkle 2** with an appcast (`appcast.xml`) | Yes | Yes, automatic with restart | Medium | A new dependency (MIT). The author must keep the EdDSA private key safe |
| C | Own updater: download the `.dmg`, mount it, replace the app | Yes | Yes | Large | Security and edge cases that Sparkle already solves (replace a running app, rights, rollback, signature check) |
| D | Homebrew cask | Only through `brew outdated` | `brew upgrade` | Small | Only for Homebrew users. It does not replace an in-app update |

**Proposal:** option B (Sparkle 2). Option D can come later as a supplement (`auto_updates true` in the cask, so Homebrew does not fight Sparkle).

Option A is a fallback, if we do not want a dependency. It gives only the notification. Sparkle gives the notification and the installation, so A is not a necessary first step.

## 4. How Sparkle works

1. The app reads `SUFeedURL` from `Info.plist`. This is the address of the appcast.
2. The appcast is an RSS (XML) file. Each item has a version, a download URL, a size, an EdDSA signature and release notes.
3. Sparkle compares `sparkle:version` with `CFBundleVersion` of the running app. A higher number is an update.
4. Sparkle downloads the `.dmg` and checks two things:
   - the EdDSA signature of the file against `SUPublicEDKey` in `Info.plist`,
   - the Apple code signature of the new app. The Team ID must be the same as in the running app.
5. Sparkle replaces `Minutes.app` in place and starts the new version.

The app has no App Sandbox (ADR-0011). Thus Sparkle needs no XPC installer service. This keeps the integration simple.

## 5. Distribution of the files

| File | Where | Who makes it |
|---|---|---|
| `Minutes-<version>.dmg` | GitHub release asset (as now) | `release.sh` |
| `appcast.xml` | GitHub Pages: `https://softverse-space.github.io/minutes/appcast.xml` (file `apps/site/appcast.xml`) | `release.sh` with Sparkle `generate_appcast` or `sign_update` |
| Release notes | Inside the appcast item (`<description>`, HTML from `CHANGELOG.md`) | `release.sh` |

- The download URL in the appcast points to the GitHub release asset: `https://github.com/softverse-space/minutes/releases/download/v<version>/Minutes-<version>.dmg`.
- The appcast is in git. The history of the appcast is in the history of the repository.
- The `pages.yml` workflow publishes the appcast together with the site (ADR-0028). The author pushes the appcast to `main` only after the GitHub release with the `.dmg` exists. Otherwise the app finds an update that it cannot download.

**Alternative:** the appcast as a release asset with the address `https://github.com/softverse-space/minutes/releases/latest/download/appcast.xml`. It needs no Pages commit. But a draft or a wrong "latest" release changes the feed at once, and there is no history in git. Proposal: GitHub Pages.

## 6. User flows

### U1 – First start after the installation

1. On the second start, Sparkle asks: "Check for updates automatically?" (the standard Sparkle question).
2. The user selects Yes or No. Settings → General shows the same choice later.
3. Default interval: one day (`SUScheduledCheckInterval = 86400`).

### U2 – A new version exists (automatic check)

1. The app checks the appcast in the background.
2. Minutes is a menu bar app (`LSUIElement`). Sparkle does not open a window at a random time. The app uses "gentle reminders":
   - The menu bar icon gets a small badge.
   - The popover shows a row: "Minutes 1.1.0 is available" with the button **Update**.
   - The app can show one system notification.
3. The user clicks **Update**. Sparkle opens its window with the release notes and the buttons **Install Update**, **Remind Me Later**, **Skip This Version**.

### U3 – Install the update

1. The user clicks **Install Update**.
2. Sparkle downloads and checks the `.dmg`.
3. Case A – the app is idle: Sparkle replaces the app and restarts it.
4. Case B – a recording, a transcription, a summary or a cleanup runs:
   - The app does not restart. It shows: "The update installs when the current job is done."
   - The app installs the update when the last job ends, or when the user quits the app.

### U4 – Manual check

1. The user clicks **Check for Updates…** in the popover menu or in Settings → About.
2. Sparkle shows the result: a new version, or "You have the latest version".

### U5 – Automatic download (optional setting)

1. Settings → General: **Download and install updates automatically** (Sparkle `SUAutomaticallyUpdate`). Default: off.
2. When it is on, Sparkle downloads the update in the background and installs it when the user quits the app. The rule from U3 case B applies.

## 7. Changes in the app

| Area | Change |
|---|---|
| `project.yml` | Add the package `https://github.com/sparkle-project/Sparkle`, exact version (as WhisperKit) |
| `Info.plist` | `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` (not set, so Sparkle asks), `SUScheduledCheckInterval` |
| New `UpdateController` (`App/`) | Owns `SPUStandardUpdaterController`. Is the delegate: gentle reminders, postpones the install while a job runs (`updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`, `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`) |
| `AppModel` / `JobCoordinator` | Gives `UpdateController` one value: "is a job running". Calls the stored install block when the last job ends |
| Popover | Row "Update available" and **Check for Updates…** in the menu |
| Settings → General | **Check for updates automatically**, **Download and install updates automatically** |
| Settings → About | **Check for Updates…**, the current version and build, the Sparkle license (MIT) |
| String Catalog | New texts in English and Slovak |
| Debug build | No `SUFeedURL`, or the updater is off. A development build must not replace itself with the release build (other signature, see the memory about Screen Recording permission) |

## 8. Changes in the release

1. Increase `CURRENT_PROJECT_VERSION` for each release. Sparkle compares `CFBundleVersion`. Today it is `1` for 1.0.0.
2. One time: run Sparkle `generate_keys`. The private key stays in the author's Keychain. Put the public key in `Info.plist`.
3. Make a backup of the private key (`generate_keys -x`) to a safe place outside the repository. Without the key, the author cannot sign updates for the installed apps.
4. Extend `release.sh`:
   1. After notarization and `stapler`, run `sign_update Minutes-<version>.dmg`. It gives the EdDSA signature and the length.
   2. Add a new item to `apps/site/appcast.xml`: version, build, `minimumSystemVersion` 15.0, URL, signature, length, release notes from `CHANGELOG.md`.
5. Create the GitHub release with the `.dmg` (as now).
6. Push the appcast to `main`. `pages.yml` publishes it.

The order 5 → 6 is important: the `.dmg` must exist before the appcast announces it.

## 9. Security and privacy

- **Two signatures.** Sparkle checks the EdDSA signature and the Apple Developer ID signature. An attacker needs both keys.
- **HTTPS only.** GitHub and GitHub Pages use HTTPS.
- **No telemetry.** Sparkle "system profiling" is off (`SUEnableSystemProfiling = NO`). The request contains only the app version in the User-Agent. GitHub sees the IP address, the same as for any download.
- **Data boundary.** ADR-0010 says "no telemetry". The update check is not telemetry. The user can turn it off. Update the data boundary text in the wiki and in the user guide.
- **Permissions (TCC).** macOS keeps the Screen Recording and Microphone permissions when the new app has the same designated requirement (bundle ID and Team ID). Sparkle replaces the app at the same path. Test this in the first update (section 11).
- **Beta channel later.** Sparkle supports channels (`sparkle:channel`). The app can add a setting "Get beta versions" without a change of the appcast URL.

## 10. Risks

| Risk | Mitigation |
|---|---|
| The author loses the EdDSA private key | Backup outside the repository. Sparkle allows a key rotation when the Apple signature stays the same |
| The appcast announces a version without a `.dmg` | Release order (section 8). A check in `release.sh`: `curl -I` of the download URL before the appcast change |
| An update during a recording | U3 case B. The install waits for the end of the job |
| The update loses the Screen Recording permission | Test with 1.0.x → 1.1.0. If it happens, document it in the release notes |
| Users of 1.0.0 have no Sparkle | They install 1.1.0 manually one time. Later versions update automatically. Say this in the release notes of 1.1.0 |
| The `.dmg` contains the `Applications` link and a volume | Sparkle supports `.dmg` and finds the app inside. No change needed |

## 11. Plan

1. Accept ADR-0031.
2. Spike: add Sparkle, a test appcast on a local HTTP server, two local builds with the Developer ID signature (1.1.0 build 2 → 1.1.1 build 3). Check the install, the restart and the permissions.
3. `UpdateController`, UI texts (EN and SK), settings.
4. Postpone the install while a job runs.
5. `release.sh`: `sign_update` and the appcast item.
6. Release 1.1.0 manually. Users of 1.0.0 install it one time from the `.dmg`.
7. Release 1.1.1 as the first automatic update. Check it on a second Mac.
8. Update the user guide (`apps/site/index.html`, EN and SK), `CHANGELOG.md`, the wiki pages `architecture`, `ui`, `roadmap`.

## 12. Open questions

- **Q1:** Ask about automatic checks on the second start (Sparkle default), or turn them on by default and tell the user in the release notes? Proposal: the Sparkle question.
- **Q2:** Automatic download and install (U5) on or off by default? Proposal: off.
- **Q3:** Release notes in Slovak too? Sparkle supports `xml:lang` per description. Proposal: English only, as `CHANGELOG.md`.
- **Q4:** Keep the badge on the menu bar icon, or only the popover row? Proposal: a small dot with a color that no other icon state uses.
