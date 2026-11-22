import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    var thumbnail: NSImage?

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool { lhs.id == rhs.id && lhs.thumbnail === rhs.thumbnail }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MicrophoneInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

enum SourceCatalog {
    static var hasScreenRecordingPermission: Bool { ScreenshotMode.isOn || CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time. Later the user must allow it in System Settings.
    static func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    static var microphoneAuthorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func microphones() -> [MicrophoneInfo] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        return session.devices.map { MicrophoneInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    static var defaultMicrophoneID: String? { AVCaptureDevice.default(for: .audio)?.uniqueID }

    static func shareableDisplays() async throws -> [SCDisplay] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
    }

    /// Main actor: `name(for:)` reads `NSScreen`, which AppKit supports only on the main thread.
    /// The ScreenCaptureKit calls still suspend and do not block it.
    @MainActor
    static func displays(withThumbnails: Bool) async throws -> [DisplayInfo] {
        let displays = try await shareableDisplays()
        var result: [DisplayInfo] = []
        for display in displays {
            var info = DisplayInfo(id: display.displayID, name: name(for: display.displayID), width: display.width, height: display.height)
            if withThumbnails { info.thumbnail = try? await thumbnail(for: display) }
            result.append(info)
        }
        return result
    }

    private static func thumbnail(for display: SCDisplay) async throws -> NSImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let width = 320
        configuration.width = width
        configuration.height = max(1, Int(Double(width) * Double(display.height) / Double(max(display.width, 1))))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    @MainActor
    private static func name(for displayID: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) {
            return screen.localizedName
        }
        return CGDisplayIsBuiltin(displayID) != 0 ? String(localized: "Built-in display") : String(localized: "Display \(displayID)")
    }
}
