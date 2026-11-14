import Foundation

/// A unique folder in the temporary directory. It is deleted when the value goes away,
/// so tests do not leave files behind.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "oms-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

extension TimeZone {
    static let utc = TimeZone(identifier: "UTC")!
}
