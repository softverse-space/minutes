import Foundation

public enum OutputLanguage {
    /// Supported output languages: code and English name (used in the prompt).
    public static let all: [(code: String, name: String)] = [
        ("sk", "Slovak"),
        ("en", "English"),
        ("cs", "Czech"),
        ("de", "German"),
    ]

    public static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }
}

public struct SummaryRequest: Sendable {
    /// `nil` means a custom instruction replaces the template.
    public var template: SummaryTemplate?
    public var customInstruction: String
    public var detail: DetailLevel
    public var language: String
    public var extraInstruction: String
    public var meetingDate: Date
    /// Time zone of the recording, so the meeting day in the prompt matches the day it happened.
    public var timeZone: TimeZone
    /// Path to `frame-at.sh`. `nil` when frames are not available.
    public var frameToolPath: String?

    public init(template: SummaryTemplate?, customInstruction: String = "", detail: DetailLevel, language: String,
                extraInstruction: String = "", meetingDate: Date, timeZone: TimeZone = .current,
                frameToolPath: String?) {
        self.template = template
        self.customInstruction = customInstruction
        self.detail = detail
        self.language = language
        self.extraInstruction = extraInstruction
        self.meetingDate = meetingDate
        self.timeZone = timeZone
        self.frameToolPath = frameToolPath
    }
}

public enum PromptBuilder {
    public static let filenameMarker = "<!-- filename:"
    public static let topicMarker = "<!-- topic:"

    public static func build(_ request: SummaryRequest, details: DetailLevelCatalog) -> String {
        var parts: [String] = []

        if let template = request.template {
            parts.append(template.body)
        } else {
            parts.append("Write meeting minutes that follow this instruction from the user:\n\n\(request.customInstruction.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if let detail = details.instructions[request.detail] {
            parts.append(detail)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = request.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        parts.append("""
        Output language: \(OutputLanguage.name(for: request.language)) (\(request.language)).
        Meeting date: \(formatter.string(from: request.meetingDate)).
        """)

        let extra = request.extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            parts.append("Additional instruction from the user:\n\(extra)")
        }

        let framesPolicy = request.template?.frames ?? .auto
        if let tool = request.frameToolPath, framesPolicy != .never {
            let when = framesPolicy == .always
                ? "Request a frame at every important change on the screen."
                : "Request a frame only when the speech depends on the screen."
            parts.append("""
            Screen frames: \(when)
            Command (keep the path in quotes): `"\(tool)" <hh:mm:ss>`
            The time has two digits in each part, for example `00:07:42`. Add nothing else to the command.
            The command works only in the session folder. Do not change the working folder.
            Times in the transcript match the time in the video.
            """)
        } else {
            parts.append("Screen frames are not available. Use only the transcript.")
        }

        parts.append("""
        The first line of the output must be: `\(topicMarker) <topic> -->`
        `<topic>` is 2–3 words without diacritics, in lowercase, joined with underscores (for example `sprint_planning`).
        If the user requests an output file name, put a second line: `<!-- filename: <name>.md -->`.
        Follow file naming instructions in the additional or custom instruction. Use the meeting date above.
        Preserve the requested spelling. Return only a file name, without a folder or path, with the .md extension.
        If no file name is requested, omit this line. The app saves the file; do not write it yourself.
        Then write the minutes.
        """)

        return parts.joined(separator: "\n\n")
    }
}

public enum SummaryOutput {
    /// Reads optional file metadata without treating comments in the minutes as metadata.
    public static func extract(from output: String) -> (topic: String?, fileName: String?, body: String) {
        var lines = output.components(separatedBy: "\n")
        var fileName: String?
        if let index = lines.prefix(5).firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(PromptBuilder.filenameMarker)
        }) {
            let line = lines.remove(at: index).trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("-->") {
                fileName = String(line.dropFirst(PromptBuilder.filenameMarker.count).dropLast(3))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        let result = extractTopic(from: lines.joined(separator: "\n"))
        return (result.topic, fileName, result.body)
    }

    /// Removes the topic marker line and returns the topic slug.
    public static func extractTopic(from output: String) -> (topic: String?, body: String) {
        var lines = output.components(separatedBy: "\n")
        guard let index = lines.prefix(5).firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(PromptBuilder.topicMarker) }) else {
            return (nil, output.trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
        }
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        let raw = line
            .replacingOccurrences(of: PromptBuilder.topicMarker, with: "")
            .replacingOccurrences(of: "-->", with: "")
        lines.removeSubrange(0...index)
        let slug = slugify(raw)
        return (slug.isEmpty ? nil : slug, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
    }

    /// Lowercase ASCII words joined by `_`, max. 4 words.
    public static func slugify(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.prefix(4).joined(separator: "_")
    }
}
