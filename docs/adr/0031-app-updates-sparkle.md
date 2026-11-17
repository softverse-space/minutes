# ADR-0031: App updates with Sparkle and an appcast on GitHub Pages

- **Status:** Accepted
- **Date:** 2026-11-17
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0011](0011-distribution-signed-dmg.md), [ADR-0021](0021-first-release-packaging.md) (manual updates)
- **Specification:** [app-updates](../specs/app-updates.md)

## Context

The app does not know that a new version exists. The user must check GitHub and replace the app manually. The repository and the releases are public on GitHub. The app is signed with Developer ID, notarized and has no App Sandbox. Updates must not interrupt a recording and must keep the Screen Recording permission. The app sends no telemetry (ADR-0010).

## Options

1. **Check the GitHub API and open the release page** – small work, no dependency. Only a notification, the installation stays manual. API rate limit.
2. **Sparkle 2 with an appcast** – notification and installation with restart. EdDSA and Apple signature check. A new dependency (MIT) and a private key that the author must keep safe.
3. **Own updater** – full control. Large work and security risk. Sparkle already solves it.
4. **Homebrew cask only** – small work. Only for Homebrew users.

## Decision

We select option 2.

- The app uses Sparkle 2 (Swift Package, exact version).
- The appcast is `apps/site/appcast.xml`, published on `https://softverse-space.github.io/minutes/appcast.xml` (ADR-0028).
- The `.dmg` stays a GitHub release asset. The appcast item points to it.
- `scripts/appcast.sh` signs the `.dmg` with the EdDSA key (`sign_update`) and adds the appcast item after the GitHub release exists. `release.sh` refuses to notarize a build without the public key.
- The EdDSA private key is only in the author's Keychain and in a backup outside the repository.
- The author makes releases locally on the author's Mac: `release.sh`, the GitHub release, `appcast.sh`. The team has one person. The signing keys stay in one place and no CI system has them.
- A release through GitHub Actions is possible later, when more people make releases. It needs a new ADR and these protections: the environment `release` with a required reviewer, protected `v*` tags, 2FA for all people with write access, actions pinned to a commit SHA. The public key does not change, so the installed apps continue to update.
- The app asks before the first automatic check. Automatic download and install is off by default.
- The app never restarts for an update while a job runs. It installs the update when the job ends or when the user quits.
- Sparkle system profiling is off.
- The Debug build does not check for updates. Only the Release configuration has `SUFeedURL`.
- A scheduled update shows as a gentle reminder: a blue dot next to the idle menu bar icon and a row in the popover. Sparkle opens its window only when the user clicks.
- Problem reports go to GitHub Issues with the template `.github/ISSUE_TEMPLATE/bug_report.yml`. Questions go to Discussions.
- Settings → About shows that Minutes is open source (Apache 2.0) and links to the repository, the release notes, the user guide and a problem report. `ProjectLinks` in OMSCore keeps the URLs in one place. The problem report contains only the app and macOS versions, and the user sends it in the browser.

## Consequences

- Each release increases `CURRENT_PROJECT_VERSION` (Sparkle compares `CFBundleVersion`).
- Users of 1.0.0 install the first version with Sparkle manually one time.
- The update check is a network request to GitHub. It is not telemetry. The data boundary text in the wiki and the user guide must say this.
- A lost private key blocks updates until a key rotation. We keep a backup.
- We must test that the update keeps the Screen Recording permission.
- Homebrew cask can come later with `auto_updates true`.
