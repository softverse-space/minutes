import OMSCore
import SwiftUI

struct SummarySettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.opencodePath) private var opencodePath = ""
    @AppStorage(SettingsKey.opencodeModel) private var opencodeModel = ""
    @AppStorage(SettingsKey.opencodeAgent) private var opencodeAgent = "meeting-summary"
    @AppStorage(SettingsKey.defaultTemplate) private var defaultTemplate = "standard"
    @AppStorage(SettingsKey.defaultDetail) private var defaultDetail = DetailLevel.medium.rawValue
    @AppStorage(SettingsKey.defaultLanguage) private var defaultLanguage = "sk"
    @AppStorage(SettingsKey.customTemplatesFolder) private var templatesFolder = ""
    @State private var agentInSync = false
    @State private var agentMessage: String?
    @State private var showAdvanced = false
    @State private var detectedOpencode: String?
    @State private var ffmpegAvailable = false
    @State private var systemPromptEdited = false
    @State private var confirmPromptReset = false
    @State private var promptMessage: String?

    private var opencodeFound: Bool {
        opencodePath.isEmpty ? detectedOpencode != nil : FileManager.default.isExecutableFile(atPath: opencodePath.expandingTildeInPath)
    }

    var body: some View {
        Form {
            Section {
                DefaultModelPicker(engine: .opencode, listed: model.engineModels[.opencode] ?? [])
                Picker("Template", selection: $defaultTemplate) {
                    ForEach(model.templates) { Text($0.name).tag($0.id) }
                }
                Picker("Detail", selection: $defaultDetail) {
                    ForEach(DetailLevel.allCases) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                Picker("Summary language", selection: $defaultLanguage) {
                    ForEach(OutputLanguage.all, id: \.code) { Text(OutputLanguage.localizedName(for: $0.code)).tag($0.code) }
                }
            } header: {
                Text("Defaults")
            } footer: {
                Text("You can change them for each summary. The model list comes from the opencode models command.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                FolderRow(title: "Folder", path: $templatesFolder)
                LabeledContent("Loaded") {
                    HStack {
                        Text("\(model.templates.count) templates").foregroundStyle(.secondary)
                        Button("Reload templates", systemImage: "arrow.clockwise") { model.reloadTemplates() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Reload templates")
                    }
                }
            } header: {
                Text("Templates")
            } footer: {
                Text("A template is a Markdown file with the header fields id, name, description, frames, detail and language. Use standard.md as a sample.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("File") {
                    HStack(spacing: 8) {
                        Text(systemPromptEdited ? "Edited" : "Default").foregroundStyle(.secondary)
                        Button("Edit") { EditorApp.open(BundledResources.userSystemPromptFile) }
                        Menu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([BundledResources.userSystemPromptFile])
                            }
                            Button("Reset to default…") { confirmPromptReset = true }
                                .disabled(!systemPromptEdited)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                LabeledContent("Video frames") {
                    StatusLabel(text: ffmpegAvailable ? "Available (ffmpeg)" : "Not available – ffmpeg is missing",
                                ok: ffmpegAvailable)
                }
                if let promptMessage {
                    Text(promptMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("System prompt")
            } footer: {
                Text("The summary rules are the same for all models. The app keeps them in ~/Library/Application Support/OfflineMeetingSummary/prompts/meeting-summary.md. Your changes apply from the next summary. A new app version updates the file only when you did not edit it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("opencode") {
                    StatusLabel(text: opencodeFound ? "Found" : "Not found (brew install opencode)", ok: opencodeFound)
                }
                LabeledContent("Agent \(opencodeAgent)") {
                    if opencodeAgent != OpenCodeAgent.managedName {
                        Text("Custom agent").foregroundStyle(.secondary)
                    } else if agentInSync {
                        StatusLabel(text: "Matches the prompt", ok: true)
                    } else {
                        Button("Update") { syncAgent() }
                    }
                }
                if let agentMessage {
                    Text(agentMessage).font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Path to opencode", text: $opencodePath,
                              prompt: Text(detectedOpencode ?? String(localized: "automatic")))
                    TextField("Agent", text: $opencodeAgent)
                }
            } header: {
                Text("OpenCode")
            } footer: {
                Text("OpenCode gets the system prompt as the agent \(OpenCodeAgent.managedName). The app creates it at launch and before each summary and overwrites manual changes. Set up a custom agent under a different name.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(SummaryEngine.allCases.filter(\.isCloudOnly)) { engine in
                CloudEngineSection(engine: engine)
            }
        }
        .task {
            refreshPromptState()
            await model.refreshModels()
        }
        .task(id: opencodePath) {
            detectedOpencode = ProcessRunner.which(SummaryEngine.opencode.executableName)?.path
            ffmpegAvailable = SummaryService.isFfmpegAvailable
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPromptState()
        }
        .confirmationDialog("Reset the system prompt to the default?", isPresented: $confirmPromptReset) {
            Button("Reset", role: .destructive) { resetSystemPrompt() }
        } message: {
            Text("Your changes in the system prompt will be lost.")
        }
        .onChange(of: opencodeModel) { model.formModelID = AppModel.defaultModelChoice.id }
        .onChange(of: defaultTemplate) { model.formTemplateID = defaultTemplate }
        .onChange(of: defaultDetail) { model.formDetail = DetailLevel(rawValue: defaultDetail) ?? .medium }
        .onChange(of: defaultLanguage) { model.formLanguage = defaultLanguage }
    }

    private func refreshPromptState() {
        systemPromptEdited = BundledResources.isSystemPromptEdited
        agentInSync = BundledResources.isAgentInSync
    }

    private func resetSystemPrompt() {
        do {
            try BundledResources.resetUserSystemPrompt()
            promptMessage = nil
        } catch {
            promptMessage = error.localizedDescription
        }
        refreshPromptState()
    }

    private func syncAgent() {
        do {
            try BundledResources.syncOpenCodeAgent()
            agentInSync = BundledResources.isAgentInSync
            agentMessage = String(localized: "The agent is in ~/.config/opencode/agent/meeting-summary.md")
        } catch {
            agentMessage = error.localizedDescription
        }
    }
}

/// Settings for one cloud-only engine (Claude, Codex): opt-in, CLI status, path and model.
struct CloudEngineSection: View {
    let engine: SummaryEngine
    @AppStorage private var enabled: Bool
    @AppStorage private var path: String
    @Environment(AppModel.self) private var model
    @State private var detected: String?

    init(engine: SummaryEngine) {
        self.engine = engine
        _enabled = AppStorage(wrappedValue: false, SettingsKey.enabled(for: engine))
        _path = AppStorage(wrappedValue: "", SettingsKey.path(for: engine))
    }

    private var found: Bool {
        path.isEmpty ? detected != nil : FileManager.default.isExecutableFile(atPath: path.expandingTildeInPath)
    }

    var body: some View {
        Section {
            Toggle("Offer \(engine.displayName) for summaries", isOn: $enabled)
            LabeledContent("\(engine.displayName) CLI") {
                StatusLabel(text: found ? "Found" : "Not found", ok: found)
            }
            if enabled {
                TextField("Path to \(engine.executableName)", text: $path,
                          prompt: Text(detected ?? String(localized: "automatic")))
                DefaultModelPicker(engine: engine, listed: model.engineModels[engine] ?? engine.presetModels)
            }
        } header: {
            Text("\(engine.displayName) (cloud)")
        } footer: {
            Label("\(engine.displayName) runs in the \(engine.cloudVendor ?? "") cloud. The transcript and selected frames leave the Mac. The app never selects it by itself – you select it for a specific summary.",
                  systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .task(id: path) { detected = ProcessRunner.which(engine.executableName)?.path }
        .task(id: enabled) {
            if enabled { model.engineModels[engine] = await SummaryService.listModels(for: engine) }
        }
    }
}

