import SwiftUI

struct RecordingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(.red).frame(width: 12, height: 12)
                    .opacity(Int(model.now.timeIntervalSince1970 * 2) % 2 == 0 ? 1 : 0.4)
                Text(model.phase == .stopping ? "Saving recording…" : "Recording").font(.headline)
                Spacer()
                Text(model.elapsedText).font(.title2.monospacedDigit())
            }

            HStack(spacing: 12) {
                if !model.recordingCapturesScreen {
                    Label("Audio only", systemImage: "waveform").foregroundStyle(.secondary)
                } else if let display = model.selectedDisplay {
                    Label(display.name, systemImage: "display").foregroundStyle(.secondary)
                }
                if let number = model.activePartNumber, number > 1 {
                    Label("Part \(number)", systemImage: "square.stack").foregroundStyle(.secondary)
                }
            }

            SectionTitle(text: "Audio")
            if model.captureSystemAudio {
                sourceRow(title: "System audio", icon: "speaker.wave.2", mutedIcon: "speaker.slash", level: model.systemLevel,
                          muted: model.systemMuted) { model.setMuted($0, microphone: false) }
            }
            if model.captureMicrophone && !model.microphoneDenied {
                sourceRow(title: "Microphone", icon: "mic", mutedIcon: "mic.slash", level: model.microphoneLevel,
                          muted: model.microphoneMuted) { model.setMuted($0, microphone: true) }
            }

            Button {
                Task { await model.stopSession() }
            } label: {
                Label("Stop recording", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.phase != .recording)
        }
    }

    private func sourceRow(title: LocalizedStringKey, icon: String, mutedIcon: String, level: Float, muted: Bool,
                           set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Image(systemName: muted ? mutedIcon : icon).frame(width: 20).accessibilityHidden(true)
            Text(title)
            Spacer()
            LevelMeter(level: muted ? 0 : level).accessibilityHidden(true)
            Toggle(title, isOn: Binding(get: { !muted }, set: { set(!$0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}
