import Foundation

/// Converts the Markdown of a summary to HTML for the clipboard. Mail, Teams, Word and Pages then paste formatted text.
///
/// The converter supports the subset that summaries use: headings, paragraphs, nested lists, tables, quotes,
/// code blocks, rules, bold, italic, inline code and links. Styles are inline, because many mail apps drop `<style>`.
public enum MarkdownHTML {
    /// A full HTML document with a UTF-8 declaration.
    public static func document(_ markdown: String) -> String {
        """
        <html><head><meta charset="utf-8"></head>\
        <body style="font-family: -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif; font-size: 14px; line-height: 1.4;">\
        \(body(markdown))</body></html>
        """
    }

    /// The HTML of the blocks, without `<html>` and `<body>`.
    public static func body(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return blocks(lines)
    }

    // MARK: Blocks

    private static func blocks(_ lines: [String]) -> String {
        var html = ""
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                html += "<pre style=\"background: #f4f4f4; padding: 8px;\"><code>\(escape(code.joined(separator: "\n")))</code></pre>\n"
            } else if let heading = heading(trimmed) {
                html += "<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>\n"
                index += 1
            } else if isRule(trimmed) {
                html += "<hr>\n"
                index += 1
            } else if index + 1 < lines.count, trimmed.contains("|"), isTableSeparator(lines[index + 1]) {
                var rows: [String] = [line]
                let separator = lines[index + 1]
                index += 2
                while index < lines.count, lines[index].contains("|"),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(lines[index])
                    index += 1
                }
                html += table(rows, separator: separator)
            } else if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    var rest = current.dropFirst()
                    if rest.hasPrefix(" ") { rest = rest.dropFirst() }
                    quoted.append(String(rest))
                    index += 1
                }
                html += "<blockquote style=\"margin-left: 0; padding-left: 10px; border-left: 3px solid #ccc; color: #555;\">\(blocks(quoted))</blockquote>\n"
            } else if listItem(line) != nil {
                var items: [ListItem] = []
                while index < lines.count {
                    let current = lines[index]
                    if let item = listItem(current) {
                        items.append(item)
                    } else if !current.trimmingCharacters(in: .whitespaces).isEmpty, leadingSpaces(current) >= 2, !items.isEmpty {
                        items[items.count - 1].text += " " + current.trimmingCharacters(in: .whitespaces)
                    } else if current.trimmingCharacters(in: .whitespaces).isEmpty,
                              index + 1 < lines.count, listItem(lines[index + 1]) != nil {
                        // A blank line between items keeps the list open (a loose list).
                    } else {
                        break
                    }
                    index += 1
                }
                var position = 0
                while position < items.count { html += list(items, &position) }
            } else {
                var paragraph: [String] = []
                while index < lines.count {
                    let current = lines[index]
                    let currentTrimmed = current.trimmingCharacters(in: .whitespaces)
                    if currentTrimmed.isEmpty || startsBlock(current, next: index + 1 < lines.count ? lines[index + 1] : nil) {
                        if !paragraph.isEmpty { break }
                    }
                    paragraph.append(currentTrimmed)
                    index += 1
                }
                html += "<p>\(paragraph.map(inline).joined(separator: "<br>\n"))</p>\n"
            }
        }
        return html
    }

    private static func startsBlock(_ line: String, next: String?) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return heading(trimmed) != nil || isRule(trimmed) || trimmed.hasPrefix(">") || trimmed.hasPrefix("```")
            || trimmed.hasPrefix("~~~") || listItem(line) != nil
            || (trimmed.contains("|") && next.map(isTableSeparator) == true)
    }

    private static func heading(_ trimmed: String) -> (level: Int, text: String)? {
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    // MARK: Lists

    private struct ListItem {
        let indent: Int
        let ordered: Bool
        let number: Int
        var text: String
    }

    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " { count += 1 } else if character == "\t" { count += 4 } else { break }
        }
        return count
    }

    private static func listItem(_ line: String) -> ListItem? {
        let indent = leadingSpaces(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let marker = trimmed.first, "-*+".contains(marker), trimmed.dropFirst().hasPrefix(" "), !isRule(trimmed) {
            return ListItem(indent: indent, ordered: false, number: 1, text: String(trimmed.dropFirst(2)))
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")", rest.dropFirst().hasPrefix(" ") else { return nil }
        return ListItem(indent: indent, ordered: true, number: Int(digits) ?? 1, text: String(rest.dropFirst(2)))
    }

    /// Renders the list that starts at `position` and its nested lists. Stops at a lower indent or a change of list type.
    private static func list(_ items: [ListItem], _ position: inout Int) -> String {
        let base = items[position].indent
        let ordered = items[position].ordered
        var html: String
        if ordered {
            let start = items[position].number
            html = start == 1 ? "<ol>" : "<ol start=\"\(start)\">"
        } else {
            html = "<ul>"
        }
        while position < items.count, items[position].indent == base, items[position].ordered == ordered {
            html += "<li>\(inline(items[position].text))"
            position += 1
            while position < items.count, items[position].indent > base {
                html += list(items, &position)
            }
            html += "</li>"
        }
        return html + (ordered ? "</ol>\n" : "</ul>\n")
    }

    // MARK: Tables

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = cells(line)
        guard !cells.isEmpty, line.contains("-") else { return false }
        return cells.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    private static func cells(_ row: String) -> [String] {
        var trimmed = row.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed.removeLast() }
        let placeholder = "\u{0}"
        return trimmed.replacingOccurrences(of: "\\|", with: placeholder)
            .components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: placeholder, with: "|").trimmingCharacters(in: .whitespaces) }
    }

    private static func table(_ rows: [String], separator: String) -> String {
        let alignments = cells(separator).map { cell -> String in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): "center"
            case (false, true): "right"
            default: "left"
            }
        }
        let border = "border: 1px solid #c8c8c8; padding: 4px 8px; vertical-align: top;"
        func row(_ line: String, tag: String) -> String {
            let extra = tag == "th" ? " background: #f0f0f0;" : ""
            let values = cells(line)
            return "<tr>" + values.indices.map { column in
                let align = column < alignments.count ? alignments[column] : "left"
                return "<\(tag) style=\"\(border)\(extra) text-align: \(align);\">\(inline(values[column]))</\(tag)>"
            }.joined() + "</tr>"
        }
        var html = "<table style=\"border-collapse: collapse;\">"
        html += "<thead>\(row(rows[0], tag: "th"))</thead><tbody>"
        html += rows.dropFirst().map { row($0, tag: "td") }.joined()
        return html + "</tbody></table>\n"
    }

    // MARK: Inline

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Inline code first, so that `*` or `_` in code stays as it is. Then links, bold and italic.
    static func inline(_ text: String) -> String {
        var html = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "`") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "`") else { break }
            html += emphasis(String(rest[..<open]))
            html += "<code style=\"background: #f0f0f0;\">\(escape(String(rest[afterOpen..<close])))</code>"
            rest = rest[rest.index(after: close)...]
        }
        return html + emphasis(String(rest))
    }

    private static func emphasis(_ text: String) -> String {
        var html = escape(text)
        html = html.replacing(/\[([^\]]+)\]\(([^)\s]+)\)/) { match in
            let url = String(match.output.2)
            let lowered = url.lowercased()
            // Only web and mail links. Other schemes stay as text.
            guard lowered.hasPrefix("https://") || lowered.hasPrefix("http://") || lowered.hasPrefix("mailto:") else {
                return String(match.output.1)
            }
            return "<a href=\"\(url)\">\(match.output.1)</a>"
        }
        html = html.replacing(/\*\*(.+?)\*\*/) { "<strong>\($0.output.1)</strong>" }
        html = html.replacing(/__(.+?)__/) { "<strong>\($0.output.1)</strong>" }
        for pattern in italicPatterns {
            html = pattern.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html),
                                                    withTemplate: "<em>$1</em>")
        }
        return html
    }

    /// `*text*` and `_text_`, but not `2 * 3 * 4` or `snake_case_name`. Swift Regex has no lookbehind.
    private static let italicPatterns: [NSRegularExpression] = [
        #"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#,
        #"(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)"#,
    ].map { try! NSRegularExpression(pattern: $0) }
}
