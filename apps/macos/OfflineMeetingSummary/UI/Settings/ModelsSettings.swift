import OMSCore
import SwiftUI

/// The tools that write the summary (OpenCode, Claude, Codex), their models and where the data goes.
struct ModelsSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.opencodeModel) private var opencodeModel = ""
    @AppStorage(SettingsKey.opencodeEnabled) private var opencodeEnabled = true
    @AppStorage(SettingsKey.claudeEnabled) private var claudeEnabled = false
    @AppStorage(SettingsKey.codexEnabled) private var codexEnabled = false

    var body: some View {
        Form {
            Section {
                Label {
                    Text("The summary sends the transcript and the selected screen frames to the provider of the model. With a local model (for example Ollama or LM Studio in OpenCode), nothing leaves the Mac. A cloud provider (for example Anthropic, OpenAI or Google) gets the data, also when you use it through OpenCode. Use a cloud model only for meetings that are not sensitive.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
                }
            } header: {
                Text("Where the data goes")
            }

            if !opencodeEnabled, !claudeEnabled, !codexEnabled {
                Section {
                    Label("All tools are off. Turn on at least one tool, or the app cannot write summaries.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(SummaryEngine.allCases) { engine in
                EngineSection(engine: engine)
            }
        }
        .formStyle(.grouped)
        .onChange(of: opencodeModel) { model.formModelID = AppModel.defaultModelChoice.id }
        .onChange(of: opencodeEnabled) { model.formModelID = AppModel.defaultModelChoice.id }
        .onChange(of: claudeEnabled) { model.formModelID = AppModel.defaultModelChoice.id }
        .onChange(of: codexEnabled) { model.formModelID = AppModel.defaultModelChoice.id }
    }
}

/// Settings for one engine. All engines always show the same rows: switch, program, default model, advanced.
/// The default model is disabled while the engine is off.
struct EngineSection: View {
    let engine: SummaryEngine
    @AppStorage private var enabled: Bool
    @AppStorage private var path: String
    @Environment(AppModel.self) private var model
    @State private var detected: String?
    @State private var showAdvanced = false

    init(engine: SummaryEngine) {
        self.engine = engine
        _enabled = AppStorage(wrappedValue: engine == .opencode, SettingsKey.enabled(for: engine))
        _path = AppStorage(wrappedValue: "", SettingsKey.path(for: engine))
    }

    /// The program that the app runs: the path from Advanced, or the one found on the search path.
    private var program: String? {
        if path.isEmpty { return detected }
        let expanded = path.expandingTildeInPath
        return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
    }

    var body: some View {
        Section {
            Toggle("Offer \(engine.displayName) for summaries", isOn: $enabled)
            LabeledContent("Program") {
                if let program {
                    StatusLabel(text: "\((program as NSString).abbreviatingWithTildeInPath)", ok: true)
                } else {
                    StatusLabel(text: "Not found", ok: false)
                }
            }
            DefaultModelPicker(engine: engine, listed: model.engineModels[engine] ?? engine.presetModels)
                .disabled(!enabled)
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                LabeledContent("Own path") {
                    TextField("Own path", text: $path, prompt: Text("automatic"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                Text("Leave the field empty to let the app find the program (see Program). It looks in /opt/homebrew/bin, /usr/local/bin, ~/.opencode/bin, ~/.local/bin, ~/.bun/bin and the PATH.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(engine.displayName)
        } footer: {
            Group {
                if let vendor = engine.cloudVendor {
                    Text("\(engine.displayName) always sends the transcript and the frames to the \(vendor) cloud.")
                } else {
                    Text("OpenCode works with any provider in your OpenCode configuration: a local model (for example Ollama or LM Studio), a company server (for example LiteLLM) or a cloud provider. New summaries start with the default model of OpenCode. When OpenCode is off, they start with Claude or Codex. The list comes from the opencode models command.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: path) { detected = ProcessRunner.which(engine.executableName)?.path }
        .task(id: enabled) {
            if enabled { model.engineModels[engine] = await SummaryService.listModels(for: engine) }
        }
    }
}
