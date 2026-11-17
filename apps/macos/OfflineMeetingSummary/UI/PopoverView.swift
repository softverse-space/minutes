import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var updates
    @Environment(\.openSettings) private var openSettings

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
        .onAppear { model.hasUnseenSummary = false }
        .task {
            model.refreshSessions()
            async let models: Void = model.refreshModels()
            await model.refreshSources()
            await models
        }
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
