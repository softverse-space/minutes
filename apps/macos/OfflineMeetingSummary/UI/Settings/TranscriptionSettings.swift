import OMSCore
import SwiftUI

struct TranscriptionSettings: View {
    @AppStorage(SettingsKey.asrMode) private var mode = AsrMode.local.rawValue
    @AppStorage(SettingsKey.whisperModel) private var whisperModel = AppSettings.defaultWhisperModel
    @AppStorage(SettingsKey.speechLanguage) private var language = "auto"
    @AppStorage(SettingsKey.autoTranscribe) private var autoTranscribe = true
    @AppStorage(SettingsKey.internalAsrURL) private var asrURL = ""
    @AppStorage(SettingsKey.internalAsrModel) private var asrModel = ""
    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var downloadProgress: Double?
    @State private var downloadError: String?
    @State private var downloadedTick = 0

    var body: some View {
        Form {
            Section {
                Picker("Transcription method", selection: $mode) {
                    ForEach(AsrMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Speech language", selection: $language) {
                    Text("Automatic").tag("auto")
                    Text("Slovak").tag("sk")
                    Text("Czech").tag("cs")
                    Text("English").tag("en")
                }
                Toggle("Transcribe automatically after recording", isOn: $autoTranscribe)
            } footer: {
                Text("For mixed Slovak and Czech, set the language manually. Automatic detection checks the language only once at the start.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if mode == AsrMode.local.rawValue {
                Section {
                    Picker("Model", selection: $whisperModel) {
                        ForEach(AppSettings.whisperModels, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    let downloaded = downloadedTick >= 0 && WhisperKitEngine.isDownloaded(whisperModel)
                    LabeledContent("Status") {
                        if downloaded {
                            StatusLabel(text: "Downloaded", ok: true)
                        } else if let progress = downloadProgress {
                            HStack {
                                ProgressView(value: progress).frame(width: 120)
                                Text(verbatim: "\(Int(progress * 100)) %").monospacedDigit().foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Download model") { download() }
                        }
                    }
                    if let downloadError {
                        Text(downloadError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Local model")
                } footer: {
                    Text("The app downloads the model from Hugging Face once. Then transcription runs without internet and the audio stays on the Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField("URL", text: $asrURL, prompt: Text(verbatim: "https://example.com/v1/audio/transcriptions"))
                    TextField("Model", text: $asrModel, prompt: Text(verbatim: "whisper-1"))
                    HStack {
                        SecureField(hasKey ? "The key is saved in Keychain" : "API key", text: $apiKey)
                        Button("Save") {
                            hasKey = Keychain.saveAsrKey(apiKey) && !apiKey.isEmpty
                            apiKey = ""
                        }
                        .disabled(apiKey.isEmpty)
                        if hasKey {
                            Button("Delete") { Keychain.saveAsrKey(""); hasKey = false }
                        }
                    }
                } header: {
                    Text("Transcription server")
                } footer: {
                    Label("The audio leaves the Mac and goes to this server (OpenAI-compatible /v1/audio/transcriptions). The video stays on the Mac.", systemImage: "exclamationmark.shield")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .task { hasKey = Keychain.hasAsrKey }
    }

    private func download() {
        downloadError = nil
        downloadProgress = 0
        let model = whisperModel
        Task {
            do {
                try await WhisperKitEngine.shared.download(model) { value in
                    // A late update must not show progress again after the download ended.
                    Task { @MainActor in if downloadProgress != nil { downloadProgress = value } }
                }
                downloadProgress = nil
                downloadedTick += 1
            } catch {
                downloadProgress = nil
                downloadError = String(localized: "Download failed: \(error.localizedDescription)")
            }
        }
    }
}
