import OMSCore
import SwiftUI

struct SessionsListView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var confirmCleanAll = false
    @State private var lastFreed: Int64?

    var body: some View {
        let items = model.sessionItems
        let filtered = items.filter { $0.matches(query) }
        let reclaimable = items.filter(\.hasSourceMedia)
        let reclaimableSize = reclaimable.reduce(0) { $0 + $1.mediaSize }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SearchField(text: $query)
                Button("Open the folder with all sessions", systemImage: "folder") {
                    model.openFolder(AppSettings.current.sessionsFolder)
                }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Open the folder with all sessions")
                Menu("More actions", systemImage: "ellipsis.circle") {
                    Button("Open sessions folder", systemImage: "folder") {
                        model.openFolder(AppSettings.current.sessionsFolder)
                    }
                    Divider()
                    Button("Free up space in all (\(FileStorage.format(reclaimableSize)))",
                           systemImage: "externaldrive.badge.minus") { confirmCleanAll = true }
                        .disabled(reclaimable.isEmpty)
                }
                    .labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More actions")
            }

            if confirmCleanAll {
                ConfirmPanel(
                    text: "Delete video and audio in all sessions (\(FileStorage.format(reclaimableSize)))? Transcripts and summaries stay, but you cannot transcribe these sessions again.",
                    onCancel: { confirmCleanAll = false }
                ) {
                    confirmCleanAll = false
                    Task { lastFreed = await model.cleanUp(reclaimable.map(\.session)) }
                }
            }
            if let lastFreed {
                Label("Freed: \(FileStorage.format(lastFreed))", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            }

            if items.isEmpty {
                EmptyState(icon: "waveform", title: "No sessions yet",
                           detail: "Start the first one on the New session tab.")
            } else if filtered.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "Nothing found",
                           detail: "Try to search by topic, date or screen.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(SessionItem.groupedByDay(filtered), id: \.day) { group in
                            Section {
                                ForEach(group.items) { item in
                                    SessionRow(item: item)
                                }
                            } header: {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Plural forms live in the String Catalog, so each count is its own string.
            Group {
                if query.isEmpty {
                    Text("\(items.count) sessions") + Text(verbatim: " · \(FileStorage.format(model.sessionsSize))")
                } else {
                    Text("Found \(filtered.count) of \(items.count)")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .animation(.smooth(duration: 0.2), value: confirmCleanAll)
        .onDisappear { lastFreed = nil }
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    @State private var hovering = false

    var body: some View {
        let session = item.session
        Button { model.focusedSession = session } label: {
            HStack(spacing: 10) {
                statusIcon.frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.topic ?? String(localized: "No summary"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(item.topic == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { model.focusedSession = session }
            Button("Open folder") { model.openFolder(session.url) }
            Button("Show in Finder") { model.reveal(session.url) }
            Button("Continue recording") { Task { await model.continueSession(session) } }
                .disabled(!model.canContinue(item) || !model.hasRecordingSources)
            Button("Merge with previous session…") { model.confirm(.merge, for: session) }
                .disabled(model.mergeProblem(item) != nil)
            Divider()
            Button("Free up space (delete video and audio)…") { model.confirm(.cleanUp, for: session) }
                .disabled(!item.hasSourceMedia || model.isBusy(session))
            Button("Delete session…", role: .destructive) { model.confirm(.delete, for: session) }
                .disabled(model.isBusy(session))
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = item.date { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        if let duration = item.metadata?.duration { parts.append(SessionFormat.duration(duration)) }
        if let count = item.metadata?.parts.count, count > 1 { parts.append(String(localized: "\(count) parts")) }
        if let display = item.metadata?.displayName, !display.isEmpty { parts.append(display) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusIcon: some View {
        let session = item.session
        if model.transcriptionJobs[session.url]?.isRunning == true || model.summaryJobs[session.url]?.isRunning == true {
            ProgressView().controlSize(.small)
        } else if item.hasOutputs {
            Image(systemName: "doc.text.fill").foregroundStyle(.green).help("The summary is done")
        } else if item.hasTranscript {
            Image(systemName: "text.bubble.fill").foregroundStyle(.blue).help("The transcript is done, the summary is not")
        } else if item.metadata?.isInterrupted == true {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                .help("The recording was interrupted")
        } else if item.metadata?.transcription == .failed {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Transcription failed")
        } else {
            Image(systemName: "waveform").foregroundStyle(.secondary).help("Recording only")
        }
    }
}
