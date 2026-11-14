import Foundation

/// Formats seconds as `hh:mm:ss` with an optional millisecond part.
public enum Timecode {
    /// - Parameter millisecondSeparator: `","` for SRT, `"."` for VTT, `nil` for no milliseconds.
    public static func format(_ seconds: Double, millisecondSeparator: String? = nil) -> String {
        let totalMilliseconds = max(0, Int((seconds * 1000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1000
        let millis = totalMilliseconds % 1000
        let base = String(format: "%02d:%02d:%02d", hours, minutes, secs)
        guard let separator = millisecondSeparator else { return base }
        return base + separator + String(format: "%03d", millis)
    }
}
