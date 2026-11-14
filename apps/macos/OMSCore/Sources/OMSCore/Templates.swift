import Foundation

/// How long and how detailed a summary is. Raw values are the section names in `_detail-levels.md`
/// and the `detail:` field of templates, so they stay stable.
public enum DetailLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case brief = "strucna"
    case medium = "stredna"
    case detailed = "detailna"

    public var id: String { rawValue }
}

public enum FramesPolicy: String, Codable, Sendable {
    case never, auto, always
}

public struct SummaryTemplate: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var frames: FramesPolicy
    public var detail: DetailLevel?
    public var language: String?
    public var body: String
    public var source: URL?

    public init(id: String, name: String, description: String = "", frames: FramesPolicy = .auto,
                detail: DetailLevel? = nil, language: String? = nil, body: String, source: URL? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.frames = frames
        self.detail = detail
        self.language = language
        self.body = body
        self.source = source
    }

    public enum ParseError: Error, Equatable {
        case missingFrontMatter
        case missingField(String)
    }

    /// Parses a Markdown file with YAML-like front matter (`key: value` lines only).
    public static func parse(_ text: String, source: URL? = nil) throws -> SummaryTemplate {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { throw ParseError.missingFrontMatter }

        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        guard let id = fields["id"], !id.isEmpty else { throw ParseError.missingField("id") }
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let language = fields["language"].flatMap { $0.isEmpty || $0 == "auto" ? nil : $0 }

        return SummaryTemplate(
            id: id,
            name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? id,
            description: fields["description"] ?? "",
            frames: fields["frames"].flatMap(FramesPolicy.init(rawValue:)) ?? .auto,
            detail: fields["detail"].flatMap(DetailLevel.init(rawValue:)),
            language: language,
            body: body,
            source: source
        )
    }
}

/// Definitions of detail levels from `_detail-levels.md` (sections `## strucna`, …).
public struct DetailLevelCatalog: Sendable {
    public var instructions: [DetailLevel: String]

    public init(instructions: [DetailLevel: String]) {
        self.instructions = instructions
    }

    public static func parse(_ text: String) -> DetailLevelCatalog {
        var result: [DetailLevel: String] = [:]
        var current: DetailLevel?
        var buffer: [String] = []
        func flush() {
            if let current { result[current] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            buffer = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                current = DetailLevel(rawValue: line.dropFirst(3).trimmingCharacters(in: .whitespaces))
            } else if current != nil {
                buffer.append(line)
            }
        }
        flush()
        return DetailLevelCatalog(instructions: result)
    }
}

public enum TemplateLoader {
    /// Loads templates from directories. Later directories override earlier ones by `id`.
    /// Files that start with `_` are not templates.
    public static func load(from directories: [URL], fileManager: FileManager = .default) -> [SummaryTemplate] {
        var byID: [String: SummaryTemplate] = [:]
        var order: [String] = []
        for directory in directories {
            guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where file.pathExtension == "md" && !file.lastPathComponent.hasPrefix("_") {
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      let template = try? SummaryTemplate.parse(text, source: file) else { continue }
                if byID[template.id] == nil { order.append(template.id) }
                byID[template.id] = template
            }
        }
        // `standard` first, then the rest in load order.
        let sorted = order.sorted { lhs, rhs in
            if lhs == "standard" { return true }
            if rhs == "standard" { return false }
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
        return sorted.compactMap { byID[$0] }
    }
}
