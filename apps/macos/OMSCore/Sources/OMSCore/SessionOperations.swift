import Foundation

/// Work that reads or writes the files of one session.
public enum SessionOperation: String, Sendable, CaseIterable {
    case recording, transcription, summary, cleanup
}

/// Decides which operations may run on a session (ADR-0023).
///
/// The rule: one operation for one session at a time. A summary reads the transcript that a transcription
/// writes, a cleanup deletes the audio that a transcription reads, and a recording writes all of them.
/// A waiting transcription counts as running. Deleting a session needs `isIdle`.
///
/// The value has no lock. Keep it in one isolation domain (the app keeps it on the main actor),
/// so a check and the start of the operation are one step.
public struct SessionOperations: Sendable {
    private var running: [String: SessionOperation] = [:]

    public init() {}

    public func operation(for session: URL) -> SessionOperation? { running[Self.key(session)] }

    public func isIdle(_ session: URL) -> Bool { operation(for: session) == nil }

    /// Starts the operation and returns `true`, or returns `false` when the session is busy.
    public mutating func begin(_ operation: SessionOperation, for session: URL) -> Bool {
        let key = Self.key(session)
        guard running[key] == nil else { return false }
        running[key] = operation
        return true
    }

    /// Ends the operation. Does nothing when another operation holds the session.
    public mutating func end(_ operation: SessionOperation, for session: URL) {
        let key = Self.key(session)
        if running[key] == operation { running[key] = nil }
    }

    private static func key(_ session: URL) -> String { session.standardizedFileURL.path }
}
