import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Recording", systemImage: "record.circle") { RecordingSettings() }
            Tab("Transcription", systemImage: "text.bubble") { TranscriptionSettings() }
            Tab("Summary", systemImage: "doc.text") { SummarySettings() }
            Tab("Models", systemImage: "cpu") { ModelsSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 640)
        .frame(minHeight: 600)
    }
}

/// A folder setting: Finder icon, short path (full path on hover), change and reveal actions.
struct FolderRow: View {
    let title: LocalizedStringKey
    @Binding var path: String

    private var url: URL { URL(filePath: path.expandingTildeInPath) }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 16, height: 16)
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                    .help(url.path)
                Menu {
                    Button("Choose another folder…") { choose() }
                    Button("Open in Finder") { NSWorkspace.shared.open(url) }
                } label: {
                    Text("Change")
                } primaryAction: {
                    choose()
                }
                .fixedSize()
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = url
        if panel.runModal() == .OK, let chosen = panel.url { path = chosen.path }
    }
}

/// A status line inside a form: colored symbol and text.
struct StatusLabel: View {
    let text: LocalizedStringKey
    let ok: Bool
    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}
