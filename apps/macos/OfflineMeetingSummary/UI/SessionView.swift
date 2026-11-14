import OMSCore
import SwiftUI

struct SessionView: View {
    @Environment(AppModel.self) private var model
    let session: SessionFolder

    @State private var pending: SessionAction?

    var body: some View {
        let item = model.item(for: session)

        VStack(alignment: .leading, spacing: 14) {
            header(item)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch pending {
                    case .cleanUp:
                        ConfirmPanel(text: "Delete video, audio and frames (\(FileStorage.format(item.mediaSize)))? The transcript and summaries stay.",
                                     onCancel: { pending = nil }) {
                            pending = nil
                            Task { await model.cleanUp([session]) }
                        }
                    case .delete:
                        ConfirmPanel(text: "Delete the whole session, including summaries? The folder moves to the Trash.",
                                     destructive: true, onCancel: { pending = nil }) {
                            pending = nil
                            model.deleteSession(session)
                        }
                    case nil:
                        EmptyView()
                    }

                    TranscriptCard(item: item)
                    SummaryCard(item: item)

                    if item.hasOutputs {
                        OutputsCard(outputs: item.outputs)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 620)
            .fixedSize(horizontal: false, vertical: true)

            footer(item)
        }
        .animation(.smooth(duration: 0.2), value: pending)
        .onAppear(perform: takePendingAction)
        .onChange(of: model.pendingSessionAction) { takePendingAction() }
    }

    /// A confirmation requested from the sessions list (context menu).
    private func takePendingAction() {
        guard let action = model.pendingSessionAction else { return }
        pending = action
        model.pendingSessionAction = nil
    }

    // MARK: Header

    private func header(_ item: SessionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Button { model.focusedSession = nil } label: {
                    Label("Sessions", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button { model.openFolder(session.url) } label: {
                    Label("Open folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open the session folder in Finder")

                Menu("More actions", systemImage: "ellipsis.circle") {
                    Button("Open folder", systemImage: "folder") { model.openFolder(session.url) }
                    Button("Show in Finder", systemImage: "magnifyingglass") { model.reveal(session.url) }
                    Divider()
                    Button("Free up space (\(FileStorage.format(item.mediaSize)))",
                           systemImage: "externaldrive.badge.minus") { pending = .cleanUp }
                        .disabled(!item.hasSourceMedia || model.isBusy(session))
                    Button("Delete session…", systemImage: "trash", role: .destructive) { pending = .delete }
                        .disabled(model.isBusy(session))
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.metadata.map { $0.startedAt.formatted(date: .abbreviated, time: .shortened) } ?? session.name)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 10) {
                    if let duration = item.metadata?.duration {
                        Label(SessionFormat.duration(duration), systemImage: "clock")
                    }
                    if let display = item.metadata?.displayName, !display.isEmpty {
                        Label(display, systemImage: "display").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }
        }
    }

    // MARK: Footer

    private func footer(_ item: SessionItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive").accessibilityHidden(true)
            if item.isStorageMeasured {
                Text(item.metadata?.mediaRemovedAt != nil
                     ? "\(FileStorage.format(item.size)) · video and audio are deleted"
                     : "\(FileStorage.format(item.size)) on disk")
            } else {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            if item.hasSourceMedia {
                Button("Free up \(FileStorage.format(item.mediaSize))") { pending = .cleanUp }
                    .help("Delete video, audio and frames. The transcript and summaries stay.")
                    .disabled(model.isBusy(session))
            }
            Button("Delete session", systemImage: "trash") { pending = .delete }
                .labelStyle(.iconOnly)
                .help("Delete session")
                .disabled(model.isBusy(session))
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Transcript

private struct TranscriptCard: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem

    var body: some View {
        let session = item.session
        let job = model.transcriptionJobs[session.url]
        let mediaRemoved = item.metadata?.mediaRemovedAt != nil

        Card {
            HStack(spacing: 10) {
                switch job {
                case .running(let message):
                    let cancelling = model.isCancelling(.transcription, session)
                    StepTitle(title: "Transcript", subtitle: cancelling ? String(localized: "Cancelling…") : message) {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Cancel") { model.cancelJobs(for: session) }
                        .disabled(cancelling)
                case .failed(let message):
                    StepTitle(title: "Transcription failed", subtitle: message) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Try again") { model.transcribe(session) }
                        .disabled(model.isBusy(session))
                default:
                    if item.hasTranscript {
                        StepTitle(title: "Transcript", subtitle: String(localized: "Done")) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Spacer()
                        Button("Transcribe again", systemImage: "arrow.clockwise") { model.transcribe(session) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help(mediaRemoved ? "Video and audio are deleted, so you cannot transcribe again" : "Transcribe again")
                            .disabled(mediaRemoved || model.isBusy(session))
                        Button("Open") { model.open(session.transcriptURL("md")) }
                    } else {
                        let subtitle = job == .cancelled
                            ? String(localized: "Cancelled. You can start it again.")
                            : String(localized: "Not done yet")
                        StepTitle(title: "Transcript", subtitle: subtitle) {
                            Image(systemName: "text.bubble").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Transcribe") { model.transcribe(session) }
                            .buttonStyle(.borderedProminent)
                            .disabled(item.metadata?.audioTracks.isEmpty ?? true || mediaRemoved || model.isBusy(session))
                    }
                }
            }
        }
    }
}

// MARK: - Summary

private struct SummaryCard: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem

    var body: some View {
        @Bindable var model = model
        let session = item.session
        let transcribed = item.hasTranscript
        let job = model.summaryJobs[session.url]
        let transcribing = model.transcriptionJobs[session.url]?.isRunning == true

        Card {
            StepTitle(title: "Summary", subtitle: nil) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    FieldLabel("Template")
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Template", selection: $model.formTemplateID) {
                            ForEach(model.templates) { template in
                                Text(template.name).tag(template.id)
                            }
                            Divider()
                            Text("Custom instruction…").tag(AppModel.customTemplateID)
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: model.formTemplateID) { model.applyTemplateDefaults() }

                        if model.formTemplateID != AppModel.customTemplateID,
                           let template = model.template(id: model.formTemplateID), !template.description.isEmpty {
                            Text(template.description)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if model.formTemplateID == AppModel.customTemplateID {
                    GridRow {
                        FieldLabel("Instruction")
                        TextEditor(text: $model.formCustomInstruction)
                            .font(.callout)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .frame(height: 110)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                if model.formCustomInstruction.isEmpty {
                                    Text("For example: “Only a list of tasks with deadlines.”")
                                        .font(.callout).foregroundStyle(.tertiary)
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator) }
                    }
                }

                GridRow {
                    FieldLabel("Detail")
                    Picker("Detail", selection: $model.formDetail) {
                        ForEach(DetailLevel.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                GridRow {
                    FieldLabel("Model")
                    ModelPicker(selection: $model.formModelID)
                }

                if let vendor = model.formModel.engine.cloudVendor {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Label("The transcript and selected frames go to \(vendor) (cloud). Use this only for meetings that are not sensitive.",
                              systemImage: "exclamationmark.icloud.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GridRow {
                    FieldLabel("Language")
                    Picker("Language", selection: $model.formLanguage) {
                        ForEach(OutputLanguage.all, id: \.code) { Text(OutputLanguage.localizedName(for: $0.code)).tag($0.code) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                GridRow {
                    FieldLabel("Extra")
                    TextField("Optional: what to focus on, what to leave out, who the summary is for…",
                              text: $model.formExtra, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                }
            }

            switch job {
            case .running(let message):
                let cancelling = model.isCancelling(.summary, session)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(cancelling ? String(localized: "Cancelling…") : message).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.cancelJobs(for: session) }
                        .disabled(cancelling)
                }
            default:
                if case .failed(let message) = job {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if job == .cancelled {
                    Label("The summary was cancelled.", systemImage: "xmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    model.summarize(session)
                } label: {
                    Label("Create summary", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!transcribed || transcribing || model.isBusy(session))

                if !transcribed {
                    Text("You can create a summary only from a finished transcript.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct OutputsCard: View {
    @Environment(AppModel.self) private var model
    let outputs: [URL]

    var body: some View {
        Card {
            StepTitle(title: "Outputs", subtitle: nil) {
                Image(systemName: "tray.full").foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(outputs, id: \.self) { url in
                    OutputRow(url: url)
                }
            }
        }
    }
}

private struct OutputRow: View {
    @Environment(AppModel.self) private var model
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button { model.open(url) } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext").foregroundStyle(Color.accentColor)
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(hovering ? .primary : .tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(url.lastPathComponent)")
        .contextMenu {
            Button("Open") { model.open(url) }
            Button("Show in Finder") { model.reveal(url) }
        }
    }
}

// MARK: - Building blocks

private struct StepTitle<Icon: View>: View {
    let title: LocalizedStringKey
    let subtitle: String?
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct FieldLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
