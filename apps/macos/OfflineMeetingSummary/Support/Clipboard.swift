import AppKit
import OMSCore

/// Copies summaries and transcripts so that the user can paste them in other apps.
@MainActor
enum Clipboard {
    /// Copies a Markdown file. With `formatted`, the clipboard also gets HTML and RTF:
    /// Mail, Teams, Word and Pages paste formatted text, and text editors paste the Markdown.
    @discardableResult
    static func copyMarkdownFile(_ url: URL, formatted: Bool) -> Bool {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard formatted else { return pasteboard.setString(markdown, forType: .string) }

        let html = MarkdownHTML.document(markdown)
        var types: [NSPasteboard.PasteboardType] = [.html, .string]
        let rtf = rtfData(fromHTML: html)
        if rtf != nil { types.insert(.rtf, at: 1) }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(html, forType: .html)
        if let rtf { pasteboard.setData(rtf, forType: .rtf) }
        pasteboard.setString(markdown, forType: .string)
        return true
    }

    /// Some apps (for example TextEdit and Notes) read only RTF.
    private static func rtfData(fromHTML html: String) -> Data? {
        guard let attributed = try? NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }
        return try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}
