# ADR-0020: App icon with light and dark appearance

- **Status:** Accepted
- **Date:** 2026-11-14
- **Decided by:** Henrich Neuschl
- **Supersedes:** the part of [ADR-0019](0019-product-name-minutes.md) about the icon (variant C3e)

## Context

After some time, the C3e icon (bubbles and a card with tasks) was weak. The original icon (a circle with a voice track) had a good idea. But it had a generic blue, an anonymous wave, competing line weights and an arc without meaning. We made the critique and the variants by the Apple principles (Simplicity, Craft, Familiarity) and the macOS icon rules.

## Options

1. **R1 – Ink and amber** – dark indigo, a glass disc, minute marks, an amber arc with a runner. Good in dark mode and at small sizes.
2. **R2 – Light paper** – white body, indigo wave, coral arc. It stands out in the Dock. In dark mode, it is too bright.
3. **R1 and R2** – the light appearance from R2, the dark from R1, through the Icon Composer format (`.icon`).

## Decision

We select option 3.

- The icon is `OfflineMeetingSummary/Resources/AppIcon.icon` (Icon Composer). The fill is a gradient. The motif is 3 SVG layers: dial, arc with runner, wave.
- Light appearance: R2. Dark and tinted appearance: R1. The tinted appearance uses the layers with a white wave for contrast.
- The script `app/design/make-app-icon.py` generates the icon. Change the icon in the script, not manually in the files.
- The menu bar icon uses the same visual language: a circle, a wave and, during transcription, an arc with a dot at the end.
- For macOS 15, Xcode also creates a classic `AppIcon.icns` from the `.icon`.

## Consequences

- To change the icon, you need only Python. `ictool` from Icon Composer renders a preview of all appearances.
- The `.icon` format has no public documentation of its keys. Appearance specializations work at the group level (`hidden-specializations`). At the layer level, `ictool` ignored them.
- The app is in the menu bar. Thus the icon shows in the Dock only during installation, and in Finder, Spotlight, notifications and About.
