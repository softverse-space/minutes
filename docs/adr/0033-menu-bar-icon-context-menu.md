# ADR-0033: Menu of the menu bar icon

- **Status:** Proposed
- **Date:** 2026-11-17
- **Decided by:** Henrich Neuschl

## Context

The app has only the menu bar icon ([ADR-0002](0002-native-macos-menu-bar-app.md), [ADR-0012](0012-menu-bar-ui-and-settings.md)). Each action needs the popover: start a recording, stop a transcription, quit. The user wants the frequent actions in a menu on a right click, like other menu bar apps.

SwiftUI `MenuBarExtra` with the window style has no API for a second menu. It does not give the `NSStatusItem`.

## Options

1. **A local event monitor** – `NSEvent.addLocalMonitorForEvents` finds a right click or a Control-click on the status bar window of the app and shows an `NSMenu` below the icon. Small change; `MenuBarExtra` and the popover stay as they are. It depends on the private class name `NSStatusBarWindow`.
2. **Own `NSStatusItem` and `NSPopover`** – full control over the clicks. But we must write again what `MenuBarExtra` gives: the popover window, the label updates and the environment of the views.

## Decision

Option 1, in `App/StatusItemMenu.swift`. A left click opens the popover as before.

The menu has:

- **Start recording** with the sources from the New session tab, or **Stop recording**. While the recording starts or saves, the item is disabled.
- **Stop transcription** – cancels the running transcription and the waiting ones.
- **Stop writing minutes** – cancels all running summaries.
- **Settings…** and **Quit Minutes**. Before the app quits, it stops a running recording correctly ([ADR-0030](0030-crash-resilient-recording.md)).

A start from the menu loads the sources first, because the popover may not have opened yet. When the start fails, the app posts a notification.

## Consequences

- The frequent actions need one click less, and they work without the popover.
- If a new macOS changes the class name of the status bar window, the menu does not open. A left click still works. Then we change to option 2.
- Verify on each new macOS version: right click, Control-click, the position of the menu, the highlight of the icon.
