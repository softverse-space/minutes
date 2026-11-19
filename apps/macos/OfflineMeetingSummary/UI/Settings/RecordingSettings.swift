import SwiftUI

struct RecordingSettings: View {
    @AppStorage(SettingsKey.videoFPS) private var fps = 5
    @AppStorage(SettingsKey.videoMaxWidth) private var maxWidth = 1920
    @AppStorage(SettingsKey.videoRetentionDays) private var retention = 0

    var body: some View {
        Form {
            Section {
                Picker("Frames per second", selection: $fps) {
                    ForEach(Array(Set([1, 2, 5, 10, 15, 30, fps])).sorted(), id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
                Picker("Max. video width", selection: $maxWidth) {
                    ForEach([1280, 1920, 2560, 3840], id: \.self) { Text(verbatim: "\($0) px").tag($0) }
                }
            } header: {
                Text("Video")
            } footer: {
                Text("For presentations and a shared screen, 2–5 frames per second are enough. The file is then small.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Delete video automatically", selection: $retention) {
                    Text("Never").tag(0)
                    Text("After 7 days").tag(7)
                    Text("After 30 days").tag(30)
                    Text("After 90 days").tag(90)
                }
            } header: {
                Text("Old videos")
            } footer: {
                Text("Audio, transcript and summaries stay. The app checks for old videos at launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Label {
                    Text("Before you record, tell the participants that you record the meeting.")
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}
