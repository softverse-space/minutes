import OMSCore
import SwiftUI

struct SessionView: View {
    @Environment(AppModel.self) private var model
    let session: SessionFolder

    @State private var pending: SessionAction?
    /// The summary form is open when the session has no summary yet, or after "New summary".
    @State private var showsSummaryForm = false

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
                    case .merge:
                        MergePanel(item: item) { pending = nil }
                    case nil:
                        EmptyView()
                    }

                    // The result comes first: when summaries exist, they are above the form.
                    if item.hasOutputs {
                        OutputsCard(item: item)
                    }

                    TranscriptCard(item: item)
                    SummaryCard(item: item, isExpanded: summaryFormOpen(item)) {
                        setSummaryForm(!showsSummaryForm)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // The popover is small: the classic scroll bar (mouse or "always show") is heavy here.
            .scrollIndicators(.never)
            .frame(maxHeight: 620)
            .fixedSize(horizontal: false, vertical: true)

            footer(item)
        }
        .animation(.smooth(duration: 0.2), value: pending)
        // A new summary closes the form again: the result is now on top.
        .onChange(of: item.outputs.count) { setSummaryForm(false) }
        .onAppear(perform: takePendingAction)
        .onChange(of: model.pendingSessionAction) { takePendingAction() }
    }

    /// Opens or closes the form in one step. An animation would resize the popover frame by frame:
    /// the whole popover flickers and the scroll bar flashes.
    private func setSummaryForm(_ open: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showsSummaryForm = open }
    }

    /// The form is always open without a summary and while a summary job runs or after it fails.
    private func summaryFormOpen(_ item: SessionItem) -> Bool {
        if !item.hasOutputs || showsSummaryForm { return true }
        switch model.summaryJobs[session.url] {
        case .running, .failed: return true
        default: return false
        }
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

                if model.canContinue(item) {
                    // A long translation does not fit next to Open folder: then only the icon shows.
                    ViewThatFits(in: .horizontal) {
                        continueButton.labelStyle(.titleAndIcon)
                        continueButton.labelStyle(.iconOnly)
                    }
                }

                Button { model.openFolder(session.url) } label: {
                    Label("Open folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open the session folder in Finder")

                Menu("More actions", systemImage: "ellipsis.circle") {
                    Button("Open folder", systemImage: "folder") { model.openFolder(session.url) }
                    Button("Show in Finder", systemImage: "magnifyingglass") { model.reveal(session.url) }
                    Button("Merge with previous session…", systemImage: "arrow.triangle.merge") { pending = .merge }
                        .disabled(model.mergeProblem(item) != nil)
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
                // The same title as in the sessions list: the topic, else the time.
                Text(item.topic ?? item.metadata.map { $0.startedAt.formatted(date: .abbreviated, time: .shortened) } ?? session.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    if item.topic != nil, let date = item.date {
                        Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .lineLimit(1)
                    }
                    if let duration = item.metadata?.duration {
                        Label(SessionFormat.duration(duration), systemImage: "clock")
                    }
                    if let count = item.metadata?.parts.count, count > 1 {
                        Label("\(count) parts", systemImage: "square.stack")
                    }
                    if let metadata = item.metadata, metadata.isImported {
                        Label(metadata.importedFileName ?? metadata.parts.first?.importedFileName ?? String(localized: "Imported"),
                              systemImage: "square.and.arrow.down")
                            .lineLimit(1)
                            .help("Imported")
                    }
                    if let display = item.metadata?.displayName ?? item.metadata?.parts.first?.displayName, !display.isEmpty {
                        Label(display, systemImage: "display").lineLimit(1)
                    }
                    if item.metadata?.isInterrupted == true {
                        Label("The recording was interrupted", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }
        }
    }

    private var continueButton: some View {
        Button { Task { await model.continueSession(session) } } label: {
            Label("Continue recording", systemImage: "record.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.red)
        .fixedSize()
        .disabled(!model.hasRecordingSources)
        .help("Record a new part into this session")
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
                        CopyButton(help: "Copy the transcript as text") {
                            Clipboard.copyMarkdownFile(session.transcriptURL("md"), formatted: false)
                        }
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
                            .disabled(!(item.metadata?.hasAudioTracks ?? false) || mediaRemoved || model.isBusy(session))
                    }
                }
            }
        }
    }
}

// MARK: - Summary

private struct SummaryCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.opencodeEnabled) private var opencodeEnabled = true
    @AppStorage(SettingsKey.claudeEnabled) private var claudeEnabled = false
    @AppStorage(SettingsKey.codexEnabled) private var codexEnabled = false
    let item: SessionItem
    let isExpanded: Bool
    let toggle: () -> Void

    private var anyEngineEnabled: Bool { opencodeEnabled || claudeEnabled || codexEnabled }

    var body: some View {
        if isExpanded {
            form
        } else {
            Card {
                HStack {
                    StepTitle(title: "Summary", subtitle: nil) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("New summary…", systemImage: "sparkles", action: toggle)
                        .disabled(model.isBusy(item.session))
                        .help("Make another summary with a different template, detail level or model")
                }
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        @Bindable var model = model
        let session = item.session
        let transcribed = item.hasTranscript
        let job = model.summaryJobs[session.url]
        let transcribing = model.transcriptionJobs[session.url]?.isRunning == true

        Card {
            HStack {
                StepTitle(title: "Summary", subtitle: nil) {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                }
                Spacer()
                if item.hasOutputs, job?.isRunning != true {
                    Button("Close", systemImage: "chevron.up", action: toggle)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Hide the summary options")
                }
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
                            .background(.background, in: RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                if model.formCustomInstruction.isEmpty {
                                    Text("For example: “Only a list of tasks with deadlines.”")
                                        .font(.callout).foregroundStyle(.tertiary)
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .overlay { RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous).strokeBorder(.separator) }
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
                    if anyEngineEnabled {
                        ModelPicker(selection: $model.formModelID)
                    } else {
                        Label("No tool is on. Turn on a tool in Settings → Models.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if anyEngineEnabled, let vendor = model.formModel.engine.cloudVendor {
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
                .disabled(!transcribed || transcribing || !anyEngineEnabled || model.isBusy(session))

                if !transcribed {
                    Text("You can create a summary only from a finished transcript.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                Button("Show prompt", systemImage: "text.magnifyingglass") { model.previewPrompt(session) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .help("Open the full text that the model gets with these settings, in your editor")
            }
        }
    }
}

private struct OutputsCard: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    private var outputs: [URL] { item.outputs }
    private var stale: Set<URL> { item.staleOutputs }

    var body: some View {
        Card {
            StepTitle(title: "Outputs", subtitle: nil) {
                Image(systemName: "tray.full").foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(outputs, id: \.self) { url in
                    OutputRow(url: url, date: item.outputDates[url], stale: stale.contains(url))
                }
            }
            if !stale.isEmpty {
                Label("Summaries marked with a clock were made before all parts were in the session.",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OutputRow: View {
    @Environment(AppModel.self) private var model
    let url: URL
    var date: Date?
    var stale = false
    @State private var hovering = false

    /// The topic from the file name, with the version: "sprint planning (2)". Else the file name.
    private var title: String {
        let name = url.lastPathComponent
        guard let topic = SessionNaming.topic(fromSummaryFileName: name) else { return url.deletingPathExtension().lastPathComponent }
        if let version = SessionNaming.version(fromSummaryFileName: name) { return "\(topic) (\(version))" }
        return topic
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { model.open(url) } label: {
                HStack(spacing: 8) {
                    Image(systemName: stale ? "clock.arrow.circlepath" : "doc.richtext")
                        .foregroundStyle(stale ? Color.secondary : Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(hovering ? .primary : .tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(url.lastPathComponent)")

            CopyButton(help: "Copy the summary. Mail, Teams and Word paste formatted text. Text editors paste Markdown.") {
                Clipboard.copyMarkdownFile(url, formatted: true)
            }
            .opacity(hovering ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
        .onHover { hovering = $0 }
        // Drag the file to Mail, Slack or Finder.
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { model.open(url) }
            Button("Copy") { Clipboard.copyMarkdownFile(url, formatted: true) }
            Button("Copy as Markdown text") { Clipboard.copyMarkdownFile(url, formatted: false) }
            ShareLink("Share…", item: url)
            Divider()
            Button("Show in Finder") { model.reveal(url) }
        }
    }
}

/// A copy icon that shows a check mark for a moment after a successful copy.
private struct CopyButton: View {
    let help: LocalizedStringKey
    let action: () -> Bool
    @State private var copied = false

    var body: some View {
        Button {
            guard action() else { return }
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(copied ? Color.green : Color.secondary)
        .help(help)
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

// MARK: - Merge

/// Confirmation of "Merge with previous session" with both sessions and the break (ADR-0029, flow F3).
private struct MergePanel: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    let onClose: () -> Void

    var body: some View {
        let previous = model.previousSession(of: item.session)
        let problem = model.mergeProblem(item)
        let gap = previous?.metadata.flatMap { target in item.metadata.flatMap { SessionMerge.gap(target: target, source: $0) } }

        Banner(tone: .info) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Merge with previous session", systemImage: "arrow.triangle.merge")
                    .font(.callout.weight(.semibold))
                if let previous {
                    row(previous)
                    row(item)
                }
                if let gap {
                    Text("Break between the sessions: \(SessionFormat.duration(gap))")
                        .font(.caption).foregroundStyle(.secondary)
                    if gap > 3600 {
                        Label("The break is longer than 60 minutes. Check that it is the same meeting.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let problem {
                    Label(problem, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("You cannot split the sessions again in the app. Older summaries stay in the session.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Button("Merge") {
                        onClose()
                        Task { await model.mergeWithPrevious(item.session) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(problem != nil)
                }
            }
        }
    }

    private func row(_ item: SessionItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(item.date?.formatted(date: .abbreviated, time: .shortened) ?? item.session.name)
            if let duration = item.metadata?.duration {
                Text(verbatim: "· \(SessionFormat.duration(duration))").foregroundStyle(.secondary)
            }
            if let topic = item.topic {
                Text(verbatim: "· \(topic)").foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.caption)
    }
}
