import OMSCore
import SwiftUI

struct IdleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            if !model.hasScreenPermission {
                PermissionBanner()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionTitle(text: "Screen")
                        Spacer()
                        if model.captureScreen {
                            Button("Reload screens", systemImage: "arrow.clockwise") { Task { await model.refreshSources() } }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Reload screens")
                        }
                        Toggle("Record the screen", isOn: $model.captureScreen.animation(.spring(duration: 0.25, bounce: 0)))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .help("Record the screen")
                    }
                    if !model.captureScreen {
                        AudioOnlyNote()
                    } else if model.displays.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading screens…").font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 90)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(model.displays) { display in
                                Button { model.selectedDisplayID = display.id } label: {
                                    DisplayTile(display: display, selected: display.id == model.selectedDisplayID)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Audio")
                Card {
                    SourceToggleRow(icon: "speaker.wave.2", title: "System audio",
                                    subtitle: "Teams, Meet, Zoom…", isOn: $model.captureSystemAudio)
                    Divider()
                    SourceToggleRow(icon: "mic", title: "Microphone", isOn: $model.captureMicrophone)
                    // On its own row, so a long device name is not cut.
                    Picker("Microphone", selection: $model.selectedMicrophoneID) {
                        ForEach(model.microphones) { mic in
                            Text(mic.name).tag(Optional(mic.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 30)
                    .disabled(!model.captureMicrophone)
                    if model.microphoneDenied {
                        Button("Microphone has no permission – open settings") { SourceCatalog.openMicrophoneSettings() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }

            if let files = model.pendingImport {
                ImportChoiceBanner(files: files)
            }

            if let offer = model.continueOffer {
                ContinueBanner(item: offer.item, interrupted: offer.interrupted)
            }

            Button {
                Task { await model.startSession() }
            } label: {
                Label(model.phase == .starting ? "Starting…" : "Start recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!model.canStart)

            // A secondary action: smaller than Start recording, so it does not compete with it.
            Button {
                model.chooseFilesToImport()
            } label: {
                Label("Import a recording…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)
            .disabled(model.isImporting)
            .help("Make a session from an audio or video file. You can also drop files here.")
        }
    }
}

/// Asks how to import more dropped files: as one session with parts or as separate sessions (ADR-0034).
struct ImportChoiceBanner: View {
    @Environment(AppModel.self) private var model
    let files: [URL]

    var body: some View {
        Banner(tone: .info) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import \(files.count) files as one session?").font(.callout.weight(.medium))
                    Text("One session makes one transcript and one summary. The files are its parts, in the order of their names.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("One session") { model.startImport(files, asOneSession: true) }
                            .buttonStyle(.borderedProminent)
                        Button("Separate sessions") { model.startImport(files, asOneSession: false) }
                            .buttonStyle(.bordered)
                    }
                }
                Spacer(minLength: 0)
                Button("Close", systemImage: "xmark") { model.pendingImport = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Shows in place of the screens when the user records only audio (ADR-0032).
struct AudioOnlyNote: View {
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio only")
                    Text("The app records no video. The minutes cannot use pictures of the screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Offer to continue the last session instead of starting a new one (ADR-0029, flow F2).
struct ContinueBanner: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    let interrupted: Bool

    var body: some View {
        Banner(tone: interrupted ? .warning : .info) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: interrupted ? "exclamationmark.circle.fill" : "arrow.clockwise.circle")
                    .foregroundStyle(interrupted ? .orange : Color.accentColor)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Continue") { Task { await model.continueSession(item.session) } }
                        .buttonStyle(.bordered)
                        .disabled(!model.hasRecordingSources)
                }
                Spacer(minLength: 0)
                Button("Close", systemImage: "xmark") { model.dismissedContinueOffers.insert(item.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var message: String {
        if interrupted { return String(localized: "The last recording was interrupted. Continue it?") }
        let end = item.metadata?.endedAt ?? Date()
        let minutes = max(1, Int(Date().timeIntervalSince(end) / 60))
        return String(localized: "Continue the last session? It stopped \(minutes) min ago.")
    }
}

/// One audio source: icon, title, optional detail and a switch on the trailing edge.
struct SourceToggleRow<Accessory: View>: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).fixedSize()
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            accessory
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

extension SourceToggleRow where Accessory == EmptyView {
    init(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.init(icon: icon, title: title, subtitle: subtitle, isOn: isOn) { EmptyView() }
    }
}

struct PermissionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Banner(tone: .warning) {
            VStack(alignment: .leading, spacing: 8) {
                Label("The app has no permission to record the screen.", systemImage: "lock.shield")
                    .font(.callout.weight(.medium))
                Text("Allow it in System Settings → Privacy & Security → Screen & System Audio Recording. Then restart the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Allow") { model.requestScreenPermission() }
                    Button("Check again") { Task { await model.refreshSources() } }
                }
            }
        }
    }
}

struct DisplayTile: View {
    let display: DisplayInfo
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous).fill(.quaternary)
                if let image = display.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(4)
                } else {
                    Image(systemName: "display").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 96)
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                        .padding(6)
                }
            }
            VStack(spacing: 1) {
                Text(display.name).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
                Text(verbatim: "\(display.width) × \(display.height)").font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.25, bounce: 0), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
