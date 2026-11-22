import Foundation
import OMSCore

/// Everything the UI shows about one session, read from disk once.
/// `SessionLibraryLoader` builds these off the main actor, so views never read files while rendering.
struct SessionItem: Identifiable, Sendable {
    let session: SessionFolder
    let metadata: SessionMetadata?
    let outputs: [URL]
    let topic: String?
    let hasTranscript: Bool
    /// Summaries older than the session transcript of a session with parts: made before a merge or a continue.
    let staleOutputs: Set<URL>
    /// Whole folder on disk.
    let size: Int64
    /// Video, audio and frames: what "Free up space" removes.
    let mediaSize: Int64

    /// `false` while the sizes are not known yet. The UI then shows progress instead of a size.
    let isStorageMeasured: Bool

    var id: URL { session.url }
    var hasOutputs: Bool { !outputs.isEmpty }
    var hasSourceMedia: Bool { mediaSize > 0 }
    var date: Date? { metadata?.startedAt }

    /// The topic from the summary. Without a summary: "Meeting at 15:30".
    var title: String {
        if let topic { return topic }
        guard let date else { return String(localized: "No summary") }
        return String(localized: "Meeting at \(date.formatted(date: .omitted, time: .shortened))")
    }

    /// When each output file was last changed. Read here, so the views do not read files while they render.
    let outputDates: [URL: Date]

    /// Reads the folder. With `measuringStorage` it walks all files: call it off the main actor.
    /// Without it, it reads only `session.json` and the list of outputs.
    init(_ session: SessionFolder, measuringStorage: Bool = true) {
        self.session = session
        metadata = try? session.loadMetadata()
        outputs = session.outputFiles()
        outputDates = Dictionary(uniqueKeysWithValues: outputs.compactMap { url in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map { (url, $0) }
        })
        topic = outputs.lazy.compactMap { SessionNaming.topic(fromSummaryFileName: $0.lastPathComponent) }.first
        hasTranscript = FileManager.default.fileExists(atPath: session.transcriptURL("md").path)
        if let metadata, metadata.parts.count > 1 {
            let date = { (url: URL) in (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
            // Without a session transcript (a new part is not transcribed yet), every summary is older than the parts.
            let transcriptDate = date(session.transcriptURL("md")) ?? .distantFuture
            staleOutputs = Set(outputs.filter { (date($0) ?? .distantPast) < transcriptDate })
        } else {
            staleOutputs = []
        }
        let sizes = measuringStorage ? session.storageSizes() : (total: 0, media: 0)
        size = sizes.total
        mediaSize = sizes.media
        isStorageMeasured = measuringStorage
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = [
            topic,
            metadata?.displayName,
            date?.formatted(date: .long, time: .shortened),
            date?.formatted(date: .numeric, time: .omitted),
            session.name,
        ].compactMap { $0 }.joined(separator: " ")
        return haystack.localizedStandardContains(query)
    }

    struct DayGroup {
        let day: Date
        let title: String
        let items: [SessionItem]
    }

    static func groupedByDay(_ items: [SessionItem]) -> [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date ?? .distantPast) }
        return groups.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) { title = String(localized: "Today") }
            else if calendar.isDateInYesterday(day) { title = String(localized: "Yesterday") }
            else if day == .distantPast { title = String(localized: "No date") }
            else { title = day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) }
            return DayGroup(day: day, title: title, items: groups[day] ?? [])
        }
    }
}

/// Loads the session list off the main actor: a recursive size scan of hundreds of folders is slow.
enum SessionLibraryLoader {
    /// Returns `nil` when the calling task was cancelled. The scan then stops after the current session.
    static func load(in folder: URL, limit: Int) async -> [SessionItem]? {
        let scan = Task.detached(priority: .userInitiated) { () -> [SessionItem]? in
            var items: [SessionItem] = []
            for session in SessionLibrary.list(in: folder, limit: limit) {
                if Task.isCancelled { return nil }
                items.append(SessionItem(session))
            }
            return items
        }
        return await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
    }
}
