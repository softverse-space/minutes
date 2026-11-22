---
name: release
description: Release a new version of Minutes end to end – version bump, CHANGELOG, signed and notarized .dmg, GitHub release, Sparkle appcast, website and README, checks after publication. Use when the user says "we release a new version", "new release", "vydávame novú verziu", "vydaj novú verziu", "spravme release" or asks to publish version X.Y.Z.
---

# Release a new version of Minutes

Follow every step in sequence. Do not skip a check. Decisions: ADR-0011, ADR-0021, ADR-0028, ADR-0031.

## Rules

- **The user runs the steps that use the signing keys:** `release.sh` (Developer ID, notarization), `notarytool`, `stapler`, `appcast.sh` (Sparkle EdDSA key in the Keychain). Give the user the exact command, one command per message block. Never put placeholders like `<notes>` in a command: zsh reads `<` and `>` as redirections.
- Never read, print or export a private key, a notary password or a Keychain item.
- `main` is protected. Every change goes through a pull request. The user merges it.
- Releases are local on the author's Mac (ADR-0031). There is no CI release.
- All repository text is in English. The website changes in English and Slovak.
- Run commands from the repository root unless a step says otherwise.

## Step 0 – Preconditions

1. `git switch main && git pull`. The working tree must be clean.
2. `gh release list -L 3` – find the last released version.
3. Read `apps/macos/CHANGELOG.md`. The section `## Unreleased` must exist and describe all changes since the last release. Compare it with `git log v<last>..main --oneline`. Add missing user-visible changes (English, STE style).
   The CHANGELOG is for users. Write one short line for each change, with what the user can do and where. Do not add links to ADRs or code, file paths or internal names. Leave out small UI details. The same text goes to the GitHub release and to the update dialog of the app.
4. Choose the version (semantic versioning). New features: minor. Only fixes: patch. Ask the user to confirm the version.
5. Run the tests and the Debug build:
   ```
   cd apps/macos/OMSCore && swift test
   cd apps/macos && xcodegen generate && xcodebuild -project OfflineMeetingSummary.xcodeproj -scheme OfflineMeetingSummary -configuration Debug -derivedDataPath build/DerivedData build
   ```
   Stop on a failure or a new warning.

## Step 1 – Prepare the version (PR "Prepare X.Y.Z")

1. `git switch -c release/prepare-X.Y.Z`
2. `apps/macos/scripts/set-version.sh X.Y.Z` – sets `MARKETING_VERSION`, increases `CURRENT_PROJECT_VERSION` by 1, renames `## Unreleased` to `## X.Y.Z – <date>`.
3. Add an entry to `wiki/log.md` (`## [date] release | Minutes X.Y.Z`).
4. Commit, push, `gh pr create`, link the PR. Ask the user to merge it.
5. After the merge: `git switch main && git pull`.

Do not change the website or the README version yet. The website must not name a version that cannot be downloaded.

## Step 2 – Build, sign, notarize (the user runs it)

1. The user runs:
   ```
   apps/macos/scripts/release.sh
   ```
2. Check the output: `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, `Authority=Developer ID Application`, `Update feed: https://softverse-space.github.io/minutes/appcast.xml`, `status: Accepted`, `source=Notarized Developer ID`.
3. **If notarization fails with a server error (for example 503),** the `.dmg` is signed but not notarized. Do not upload it. The user waits and runs these commands one by one:
   ```
   xcrun notarytool submit apps/macos/build/release/Minutes-X.Y.Z.dmg --keychain-profile minutes-notary --wait
   xcrun stapler staple apps/macos/build/release/Minutes-X.Y.Z.dmg
   spctl --assess --type open --context context:primary-signature --verbose apps/macos/build/release/Minutes-X.Y.Z.dmg
   (cd apps/macos/build/release && shasum -a 256 Minutes-X.Y.Z.dmg | tee Minutes-X.Y.Z.dmg.sha256)
   ```
   The checksum must come after `stapler`, because `stapler` changes the file. The `.sha256` file must contain only the file name, not a path.
4. If notarization is `Invalid`, get the log (`xcrun notarytool log <id> --keychain-profile minutes-notary`) and fix the cause. Do not continue.

## Step 3 – GitHub release

1. Write the release notes:
   ```
   python3 -I apps/macos/scripts/release_notes.py apps/macos/CHANGELOG.md X.Y.Z apps/macos/build/release/notes-X.Y.Z.md
   ```
2. Check that `apps/macos/build/release/Minutes-X.Y.Z.dmg` and `.sha256` exist and that `spctl` accepts the `.dmg`.
3. Ask the user to confirm, then create the release (the tag points to the current `main`):
   ```
   gh release create vX.Y.Z apps/macos/build/release/Minutes-X.Y.Z.dmg apps/macos/build/release/Minutes-X.Y.Z.dmg.sha256 --target main --title "Minutes X.Y.Z" --notes-file apps/macos/build/release/notes-X.Y.Z.md
   ```
4. Check: `gh release view vX.Y.Z --json assets` – the SHA-256 digest of the `.dmg` equals the local `.sha256`. The release is not a draft and not a pre-release, so `releases/latest` points to it.

## Step 4 – Appcast (the user runs it)

1. The user runs (macOS can ask for Keychain access to the Sparkle key):
   ```
   apps/macos/scripts/appcast.sh
   ```
2. Check `apps/site/appcast.xml`:
   - `xmllint --noout apps/site/appcast.xml`
   - the new item is first, `sparkle:version` is the new build, `shortVersionString` is X.Y.Z,
   - `length` equals the size of the `.dmg` on GitHub,
   - the EdDSA signature is valid for `SPARKLE_PUBLIC_ED_KEY` in `apps/macos/project.yml` (verify with CryptoKit `Curve25519.Signing.PublicKey.isValidSignature` in a scratch Swift script),
   - the release notes HTML is complete.

## Step 5 – Website and README (PR "Publish X.Y.Z")

1. `git switch -c release/publish-X.Y.Z` (keep the appcast change).
2. `apps/macos/scripts/sync-site-version.sh` – changes the version in `apps/site/index.html` (English and Slovak) and in `README.md`: hero, download button, install step, closing section, footer, badge.
3. Read the list of remaining old version numbers that the script prints. Change a place only if it names the current version. Sentences about history ("From version 1.1.0, …") stay.
4. Check the website for other texts that the release makes wrong: new features in the guide, FAQ, screenshots, requirements. Change every text in English and in the Slovak `SK` dictionary.
5. Commit `apps/site/appcast.xml`, `apps/site/index.html`, `README.md`. Push, `gh pr create`, link the PR. Ask the user to merge it. The appcast and the website go public together.

## Step 6 – Checks after publication

1. `gh run list --workflow pages.yml -L 1` – the Pages deployment succeeded.
2. `curl -s https://softverse-space.github.io/minutes/appcast.xml` contains `<sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>`.
3. `curl -s https://softverse-space.github.io/minutes/ | grep -c "X.Y.Z"` – the website shows the new version.
4. `curl -sIL -o /dev/null -w "%{http_code}\n" https://github.com/softverse-space/minutes/releases/download/vX.Y.Z/Minutes-X.Y.Z.dmg` gives 200.
5. Ask the user to check the update on a Mac with the previous version: Settings → About → Check for Updates…. Only the app in `/Applications` may run. A Debug build with the same bundle ID can take the Screen Recording permission. After the update, check that recording still has the permission.
6. Delete the release work files that are not needed: keep `build/release/Minutes-X.Y.Z.dmg*` only until the release is checked.
7. `git switch main && git pull`. Report to the user: version, release URL, both PRs, result of each check.

## Checklist (copy into the reply and tick off)

- [ ] Tests and Debug build pass
- [ ] CHANGELOG complete, version confirmed by the user
- [ ] PR "Prepare X.Y.Z" merged
- [ ] `.dmg` signed, notarized, stapled, checksum after stapling
- [ ] GitHub release vX.Y.Z with `.dmg` and `.sha256`, digest matches
- [ ] Appcast item valid, EdDSA signature valid
- [ ] Website and README show X.Y.Z (EN and SK)
- [ ] PR "Publish X.Y.Z" merged, Pages deployed
- [ ] Live appcast and website show X.Y.Z, download gives 200
- [ ] Update tested from the previous version, permissions kept
