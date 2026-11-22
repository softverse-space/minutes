import SwiftUI

struct RecordingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(.red).frame(width: 12, height: 12)
                    .opacity(dotOpacity)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.phase == .stopping ? "Saving recording…" : "Recording").font(.headline)
                    HStack(spacing: 10) {
                        if !model.recordingCapturesScreen {
                            Label("Audio only", systemImage: "waveform")
                        } else if let display = model.selectedDisplay {
                            Label(display.name, systemImage: "display").lineLimit(1)
                        }
                        if let number = model.activePartNumber, number > 1 {
                            Label("Part \(number)", systemImage: "square.stack")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.elapsedText)
                    .font(.system(size: 28, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Audio")
                Card {
                    if model.captureSystemAudio {
                        sourceRow(title: "System audio", icon: "speaker.wave.2", mutedIcon: "speaker.slash",
                                  level: model.systemLevel, muted: model.systemMuted) { model.setMuted($0, microphone: false) }
                    }
                    if model.captureSystemAudio && model.captureMicrophone && !model.microphoneDenied {
                        Divider()
                    }
                    if model.captureMicrophone && !model.microphoneDenied {
                        sourceRow(title: "Microphone", icon: "mic", mutedIcon: "mic.slash",
                                  level: model.microphoneLevel, muted: model.microphoneMuted) { model.setMuted($0, microphone: true) }
                    }
                }
            }

            // The same red as Start recording: both buttons control the recording.
            Button {
                Task { await model.stopSession() }
            } label: {
                Label("Stop recording", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(model.phase != .recording)
        }
    }

    /// The dot blinks once a second. With Reduce Motion it stays on.
    private var dotOpacity: Double {
        if reduceMotion || model.phase == .stopping { return 1 }
        return Int(model.now.timeIntervalSince1970 * 2) % 2 == 0 ? 1 : 0.4
    }

    private func sourceRow(title: LocalizedStringKey, icon: String, mutedIcon: String, level: Float, muted: Bool,
                           set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: muted ? mutedIcon : icon)
                .foregroundStyle(muted ? Color.secondary : Color.accentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
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
