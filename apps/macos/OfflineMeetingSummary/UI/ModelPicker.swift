import OMSCore
import SwiftUI

/// Engine and model for this summary. Each engine lists its models (`opencode models`,
/// `codex debug models`, Claude aliases). Only engines that are turned on in Settings appear.
struct ModelPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String

    var body: some View {
        Picker("Model", selection: $selection) {
            ForEach(SummaryEngine.allCases) { engine in
                EngineModelSection(engine: engine,
                                   listed: model.engineModels[engine] ?? engine.presetModels,
                                   current: model.formModel.engine == engine ? model.formModel.model : nil)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Models of one engine: its default, the listed models, the default from Settings and the current choice.
/// An engine is shown only when it is on in Settings.
private struct EngineModelSection: View {
    let engine: SummaryEngine
    let listed: [EngineModel]
    /// Model of the current choice when it uses this engine, otherwise `nil`.
    let current: String?
    @AppStorage private var enabled: Bool
    @AppStorage private var defaultModel: String

    init(engine: SummaryEngine, listed: [EngineModel], current: String?) {
        self.engine = engine
        self.listed = listed
        self.current = current
        _enabled = AppStorage(wrappedValue: engine == .opencode, SettingsKey.enabled(for: engine))
        _defaultModel = AppStorage(wrappedValue: "", SettingsKey.model(for: engine))
    }

    var body: some View {
        if enabled {
            Section(engine.displayName) {
                row(EngineModel(id: "", title: String(localized: "\(engine.displayName) default")))
                ForEach(ModelOptions.merge(listed: listed, including: [defaultModel, current ?? ""])) { option in
                    row(option)
                }
            }
        }
    }

    private func row(_ option: EngineModel) -> some View {
        Label(option.title, systemImage: "cpu")
            .tag(SummaryModelChoice(engine: engine, model: option.id).id)
    }
}

/// Default model of one engine in Settings: a list of the engine's models plus "Other…" for a typed name.
struct DefaultModelPicker: View {
    let engine: SummaryEngine
    let listed: [EngineModel]
    @AppStorage private var value: String
    @State private var typing = false

    private static let other = "__other__"

    init(engine: SummaryEngine, listed: [EngineModel]) {
        self.engine = engine
        self.listed = listed
        _value = AppStorage(wrappedValue: "", SettingsKey.model(for: engine))
    }

    var body: some View {
        Picker("Default model", selection: selection) {
            Text("Default from the \(engine.displayName) configuration").tag("")
            ForEach(ModelOptions.merge(listed: listed, including: [value])) { option in
                Text(option.title).tag(option.id)
            }
            Divider()
            Text("Other model…").tag(Self.other)
        }
        if typing {
            TextField("Model name", text: $value, prompt: Text(verbatim: listed.first?.id ?? "model-id"))
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { typing ? Self.other : value },
            set: { newValue in
                typing = newValue == Self.other
                if !typing { value = newValue }
            }
        )
    }
}
