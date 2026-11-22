import AppKit
import SwiftUI

/// A native segmented control whose segments share the full available width.
/// SwiftUI's segmented `Picker` on macOS keeps its intrinsic width.
struct SegmentedTabs: NSViewRepresentable {
    let titles: [String]
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: titles, trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fillEqually
        control.controlSize = .large
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if control.selectedSegment != selection { control.selectedSegment = selection }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func changed(_ sender: NSSegmentedControl) { selection.wrappedValue = sender.selectedSegment }
    }
}

struct SectionTitle: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }
}

/// Shared sizes, so every container in the popover has the same corners.
enum Metrics {
    /// Small elements: rows, tiles, fields.
    static let smallRadius: CGFloat = 8
    /// Containers: cards, banners, panels.
    static let cardRadius: CGFloat = 12
}

extension Color {
    /// Card fill that stands out from the popover material in light and dark mode.
    static let cardFill = Color(nsColor: NSColor(name: "cardFill") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.07)
            : NSColor.white.withAlphaComponent(0.62)
    })
}

/// A rounded container that groups related controls, like a grouped Form section.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardFill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            }
    }
}

/// The tone of a banner: a note, a question that needs attention, or a destructive confirmation.
enum BannerTone {
    case info, warning, danger

    var color: Color {
        switch self {
        case .info: .accentColor
        case .warning: .orange
        case .danger: .red
        }
    }
}

/// One style for every banner and inline panel in the popover.
struct Banner<Content: View>: View {
    var tone: BannerTone = .info
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(tone.color.opacity(0.25), lineWidth: 0.5)
            }
    }
}

struct LevelMeter: View {
    let level: Float
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(level > 0.8 ? Color.orange : Color.green)
                    .frame(width: proxy.size.width * CGFloat(min(1, sqrt(level))))
            }
        }
        .frame(width: 90, height: 8)
        .animation(.linear(duration: 0.15), value: level)
    }
}

enum SessionFormat {
    /// `46 min`, `1 hr 5 min`; under a minute `35 s`.
    static func duration(_ seconds: TimeInterval) -> String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: allowed, width: .abbreviated))
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                    .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
    }
}

struct EmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tertiary)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// Inline confirmation. The popover closes when an alert opens, so no alert is used.
struct ConfirmPanel: View {
    let text: LocalizedStringKey
    var destructive = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        Banner(tone: destructive ? .danger : .warning) {
            VStack(alignment: .leading, spacing: 8) {
                Label(text, systemImage: destructive ? "trash" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button(destructive ? "Delete" : "Yes", action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(destructive ? .red : .accentColor)
                }
            }
        }
    }
}
