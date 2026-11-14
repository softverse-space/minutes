import AppKit

/// Draws the menu bar icon (design variant C: a ring with progress).
/// All images except the recording dot are template images, so macOS colors them for light and dark menu bars.
enum MenuBarIcon {
    enum State: Equatable {
        case idle
        /// `progress` is 0…1, or `nil` when the progress is not known yet.
        case transcribing(progress: Double?)
        case summarizing
        /// A new summary is ready and the user did not open the popover yet.
        case done
        case busy
    }

    /// Canvas size in points. The ring fills almost all of it, so it looks as large as other menu bar icons.
    static let size: CGFloat = 18
    private static let lineWidth: CGFloat = 1.6
    private static var radius: CGFloat { (size - lineWidth) / 2 }
    private static var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }

    /// `phase` is a time value in seconds. It turns the spinning arc.
    static func image(_ state: State, phase: TimeInterval) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSColor.black.set()
            switch state {
            case .idle:
                ring(alpha: 1)
                waveform()
            case .transcribing(let progress):
                ring(alpha: 0.3)
                if let progress {
                    let length = max(0.03, min(1, progress))
                    arc(from: 0, length: length)
                    knob(at: length)
                } else {
                    spinner(phase)
                }
                waveform()
            case .summarizing:
                ring(alpha: 0.3)
                spinner(phase)
                sparkle(radius: 4.2)
            case .busy:
                ring(alpha: 0.3)
                spinner(phase)
            case .done:
                let badge = CGPoint(x: size - 3.4, y: size - 3.4)
                NSGraphicsContext.current?.saveGraphicsState()
                // Cut a gap around the badge so it stays readable.
                let clip = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size))
                clip.appendOval(in: NSRect(x: badge.x - 4.4, y: badge.y - 4.4, width: 8.8, height: 8.8))
                clip.windingRule = .evenOdd
                clip.addClip()
                ring(alpha: 1)
                sparkle(radius: 4.2)
                NSGraphicsContext.current?.restoreGraphicsState()
                NSBezierPath(ovalIn: NSRect(x: badge.x - 3, y: badge.y - 3, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A red dot for the recording state. It is not a template image, so it keeps its color.
    static let recordingDot: NSImage = {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor.systemRed.set()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()

    // MARK: Drawing

    private static func ring(alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setStroke()
        let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.lineWidth = lineWidth
        path.stroke()
        NSColor.black.set()
    }

    /// Arc clockwise from 12 o'clock. `from` and `length` are fractions of the full circle.
    private static func arc(from start: Double, length: Double) {
        let startAngle = 90 - 360 * start
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: startAngle,
                       endAngle: startAngle - 360 * length, clockwise: true)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.stroke()
    }

    /// A dot at the end of the progress arc, like the knob in the app icon.
    private static func knob(at fraction: Double) {
        let angle = (90 - 360 * fraction) * .pi / 180
        let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        NSBezierPath(ovalIn: NSRect(x: point.x - 2.1, y: point.y - 2.1, width: 4.2, height: 4.2)).fill()
    }

    private static func spinner(_ phase: TimeInterval) {
        arc(from: phase.truncatingRemainder(dividingBy: 1.1) / 1.1, length: 0.25)
    }

    /// Three vertical bars in the center.
    private static func waveform() {
        let bars: [(dx: CGFloat, height: CGFloat)] = [(-3, 4), (0, 7.5), (3, 5)]
        for bar in bars {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x + bar.dx, y: center.y - bar.height / 2))
            path.line(to: CGPoint(x: center.x + bar.dx, y: center.y + bar.height / 2))
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// Four-point star in the center.
    private static func sparkle(radius r: CGFloat) {
        let c = center
        let k = r * 0.2
        let path = NSBezierPath()
        path.move(to: CGPoint(x: c.x, y: c.y + r))
        path.curve(to: CGPoint(x: c.x + r, y: c.y), controlPoint1: CGPoint(x: c.x + k, y: c.y + k), controlPoint2: CGPoint(x: c.x + k, y: c.y + k))
        path.curve(to: CGPoint(x: c.x, y: c.y - r), controlPoint1: CGPoint(x: c.x + k, y: c.y - k), controlPoint2: CGPoint(x: c.x + k, y: c.y - k))
        path.curve(to: CGPoint(x: c.x - r, y: c.y), controlPoint1: CGPoint(x: c.x - k, y: c.y - k), controlPoint2: CGPoint(x: c.x - k, y: c.y - k))
        path.curve(to: CGPoint(x: c.x, y: c.y + r), controlPoint1: CGPoint(x: c.x - k, y: c.y + k), controlPoint2: CGPoint(x: c.x - k, y: c.y + k))
        path.close()
        path.fill()
    }
}
