import OMSCore
import SwiftUI

/// What the summary contains: defaults of the form, templates, the system prompt and screen frames.
/// The engines and models are in `ModelsSettings`.
struct SummarySettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.defaultTemplate) private var defaultTemplate = "standard"
    @AppStorage(SettingsKey.defaultDetail) private var defaultDetail = DetailLevel.medium.rawValue
    @AppStorage(SettingsKey.defaultLanguage) private var defaultLanguage = "sk"
    @AppStorage(SettingsKey.customTemplatesFolder) private var templatesFolder = ""
    @State private var ffmpegAvailable = false
    @State private var systemPromptEdited = false
    @State private var confirmPromptReset = false
    @State private var promptMessage: String?

    var body: some View {
        Form {
            Section {
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
                Text("The Summary card of a session starts with these values. You can change them for each summary. The default model is in the Models tab.")
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
                if let promptMessage {
                    Text(promptMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("System prompt")
            } footer: {
                Text("The rules for all summaries and all models: how to clean the transcript, what is a decision, how to write dates. Your changes apply from the next summary. A new app version updates the file only when you did not edit it. Show prompt in the Summary card shows the full text that the model gets.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("ffmpeg") {
                    StatusLabel(text: ffmpegAvailable ? "Found" : "Not found (brew install ffmpeg)", ok: ffmpegAvailable)
                }
            } header: {
                Text("Screen frames")
            } footer: {
                Text("When the speech depends on the screen, the model can cut a frame from the video at that time. The app needs ffmpeg for it. Sessions without video have no frames.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            refreshPromptState()
            ffmpegAvailable = SummaryService.isFfmpegAvailable
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPromptState()
            ffmpegAvailable = SummaryService.isFfmpegAvailable
        }
        .confirmationDialog("Reset the system prompt to the default?", isPresented: $confirmPromptReset) {
            Button("Reset", role: .destructive) { resetSystemPrompt() }
        } message: {
            Text("Your changes in the system prompt will be lost.")
        }
        .onChange(of: defaultTemplate) { model.formTemplateID = defaultTemplate }
        .onChange(of: defaultDetail) { model.formDetail = DetailLevel(rawValue: defaultDetail) ?? .medium }
        .onChange(of: defaultLanguage) { model.formLanguage = defaultLanguage }
    }

    private func refreshPromptState() {
        systemPromptEdited = BundledResources.isSystemPromptEdited
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
}
