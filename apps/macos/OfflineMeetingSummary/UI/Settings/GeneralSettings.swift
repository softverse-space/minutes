import OMSCore
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var updates
    @AppStorage(SettingsKey.sessionsFolder) private var sessionsFolder = ""
    @AppStorage(SettingsKey.editorAppPath) private var editorPath = ""
    @AppStorage(SettingsKey.appLanguage) private var appLanguage = AppLanguage.defaultValue.rawValue
    @State private var languageChanged = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private static let chooseOther = "__choose__"

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section {
                Picker("App language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .onChange(of: appLanguage) {
                    AppLanguage.apply()
                    languageChanged = true
                }
            } footer: {
                if languageChanged {
                    HStack {
                        Text("The new language applies after the app restarts.")
                        Spacer()
                        Button("Restart now") { AppRelauncher.relaunch() }
                            .disabled(model.phase != .idle)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                @Bindable var updates = updates
                // Screenshots show the switches of the released app (ScreenshotMode).
                Toggle("Check for updates automatically",
                       isOn: ScreenshotMode.isOn ? .constant(true) : $updates.automaticallyChecks)
                    .disabled(!updates.isEnabled && !ScreenshotMode.isOn)
                Toggle("Download and install updates automatically",
                       isOn: ScreenshotMode.isOn ? .constant(false) : $updates.automaticallyDownloads)
                    .disabled((!updates.isEnabled || !updates.automaticallyChecks) && !ScreenshotMode.isOn)
            } header: {
                Text("Updates")
            } footer: {
                Group {
                    if updates.isEnabled || ScreenshotMode.isOn {
                        Text("The app checks once a day. It never restarts for an update during a recording or a job.")
                    } else {
                        Text("This build does not check for updates. Only the released app from GitHub updates itself.")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                FolderRow(title: "Sessions folder", path: $sessionsFolder)
                    .onChange(of: sessionsFolder) { model.refreshSessions() }
            } header: {
                Text("Storage")
            } footer: {
                Text("Each session has its own folder with video, audio, transcript and summaries.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Open with", selection: editorSelection) {
                    Label { Text("System default app") } icon: { Image(systemName: "macwindow") }
                        .tag("")
                    if !EditorApp.defaultPath.isEmpty {
                        appOption(EditorApp.defaultPath)
                    }
                    if !editorPath.isEmpty, editorPath != EditorApp.defaultPath {
                        appOption(editorPath)
                    }
                    Divider()
                    Text("Other app…").tag(Self.chooseOther)
                }
            } header: {
                Text("Transcripts and summaries")
            } footer: {
                Text("Applies to .md, .txt, .srt, .vtt and .json files. Video opens in the default app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Label {
                    Text("The video always stays on the Mac. Transcription runs locally unless you select a server. The summary goes to the model you choose: with a local model in OpenCode, nothing leaves the Mac. The app sends no telemetry. The update check only downloads the public list of versions from GitHub.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy")
            }

        }
        .formStyle(.grouped)
    }

    private var editorSelection: Binding<String> {
        Binding(
            get: { editorPath },
            set: { value in
                if value == Self.chooseOther { chooseEditor() } else { editorPath = value }
            }
        )
    }

    private func appOption(_ path: String) -> some View {
        Label {
            Text(EditorApp.displayName(path))
        } icon: {
            Image(nsImage: Self.smallIcon(path))
        }
        .tag(path)
    }

    private static func smallIcon(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func chooseEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { editorPath = url.path }
    }
}
