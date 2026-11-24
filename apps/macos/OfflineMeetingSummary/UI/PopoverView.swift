import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var updates
    @Environment(\.openSettings) private var openSettings
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if model.phase == .recording || model.phase == .stopping {
                    RecordingView()
                } else if let session = model.focusedSession {
                    SessionView(session: session)
                        .id(session.url)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        SegmentedTabs(
                            titles: PopoverTab.allCases.map(\.title),
                            selection: Binding(
                                get: { PopoverTab.allCases.firstIndex(of: model.tab) ?? 0 },
                                set: { model.tab = PopoverTab.allCases[$0] }
                            )
                        )
                        .frame(maxWidth: .infinity)

                        switch model.tab {
                        case .record: IdleView()
                        case .sessions: SessionsListView()
                        }
                    }
                }
            }
            .padding(16)

            if let job = model.importJob {
                ImportStatusRow(job: job, progress: model.importProgress)
            }

            if let message = model.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Close", systemImage: "xmark") { model.errorMessage = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            if let version = updates.availableVersion {
                UpdateRow(version: version) { updates.checkForUpdates() }
            } else if updates.isWaitingForIdle {
                UpdateRow(version: nil, action: nil)
            }

            Divider()
            HStack {
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .disabled(model.phase != .idle)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 400)
        // Audio and video files dropped on the popover become sessions (ADR-0034).
        .dropDestination(for: URL.self) { urls, _ in
            guard model.phase == .idle || model.phase == .recording, !urls.isEmpty else { return false }
            model.requestImport(urls, askInline: true)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                DropOverlay()
            }
        }
        .onAppear { model.hasUnseenSummary = false }
        .task {
            model.refreshSessions()
            async let models: Void = model.refreshModels()
            await model.refreshSources()
            await models
        }
    }
}

/// Shows where dropped files go.
private struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                Label("Drop to import", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding(6)
            .allowsHitTesting(false)
    }
}

/// The running import, or its result when it failed or was cancelled (ADR-0034).
private struct ImportStatusRow: View {
    @Environment(AppModel.self) private var model
    let job: JobState
    let progress: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            switch job {
            case .running(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if let progress {
                        HStack(spacing: 6) {
                            ProgressView(value: progress).controlSize(.small)
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 32, alignment: .trailing)
                        }
                    } else {
                        ProgressView().progressViewStyle(.linear).controlSize(.small)
                    }
                }
                Spacer(minLength: 8)
                Button("Cancel") { model.cancelImport() }.controlSize(.small)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer()
                closeButton
            case .cancelled:
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                Text("The import was cancelled.").font(.callout)
                Spacer()
                closeButton
            case .done:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark") { model.importJob = nil }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
    }
}

/// A new version, or an update that waits for the end of the current job (ADR-0031).
private struct UpdateRow: View {
    let version: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            if let version {
                Text("Minutes \(version) is available").font(.callout)
            } else {
                Text("The update installs when the current job is done.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action {
                Button("Update", action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
