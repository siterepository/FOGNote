import Foundation
import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case html = "HTML"
    case pdf = "PDF"
    case enex = "ENEX (Evernote)"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .html: "html"
        case .pdf: "pdf"
        case .enex: "enex"
        }
    }
}

@MainActor
enum ExportService {
    static func export(note: Note, format: ExportFormat) {
        let panel = NSSavePanel()
        let base = note.title.isEmpty ? "Untitled" : note.title
        panel.nameFieldStringValue = base + "." + format.fileExtension
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try data(for: note, format: format)
            try data.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    static func data(for note: Note, format: ExportFormat) throws -> Data {
        switch format {
        case .markdown:
            return Data(markdown(for: note).utf8)
        case .html:
            return try htmlData(for: note)
        case .pdf:
            return pdfData(for: note)
        case .enex:
            return try enexData(for: note)
        }
    }

    static func markdown(for note: Note) -> String {
        var body = note.bodyPlainText
        body = body.replacingOccurrences(of: "☐ ", with: "- [ ] ")
        body = body.replacingOccurrences(of: "☑ ", with: "- [x] ")
        return "# \(note.title.isEmpty ? "Untitled" : note.title)\n\n\(body)\n"
    }

    private static func attributedBody(for note: Note) -> NSAttributedString {
        let body = NSMutableAttributedString()
        let title = NSAttributedString(
            string: (note.title.isEmpty ? "Untitled" : note.title) + "\n\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 22)]
        )
        body.append(title)
        body.append(NSAttributedString(AttributedString(rtfData: note.bodyData)))
        return body
    }

    private static func htmlData(for note: Note) throws -> Data {
        let attributed = attributedBody(for: note)
        return try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
    }

    private static func pdfData(for note: Note) -> Data {
        let pageRect = NSRect(x: 0, y: 0, width: 612, height: 792)
        let textView = NSTextView(frame: pageRect.insetBy(dx: 48, dy: 48))
        textView.textStorage?.setAttributedString(attributedBody(for: note))
        return textView.dataWithPDF(inside: textView.bounds)
    }

    private static func enexData(for note: Note) throws -> Data {
        let html = try String(data: htmlData(for: note), encoding: .utf8) ?? note.bodyPlainText
        let bodyOnly = html
            .replacingOccurrences(of: "<!DOCTYPE[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</?(html|head|body|meta)[^>]*>", with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        let created = compactDate(note.createdAt)
        let updated = compactDate(note.modifiedAt)
        let tags = note.tags.map { "<tag>\($0.name)</tag>" }.joined()
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE en-export SYSTEM "http://xml.evernote.com/pub/evernote-export4.dtd">
        <en-export export-date="\(compactDate(.now))" application="FOGNote" version="1.0">
        <note><title>\(escape(note.title.isEmpty ? "Untitled" : note.title))</title>
        <content><![CDATA[<?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
        <en-note>\(bodyOnly)</en-note>]]></content>
        <created>\(created)</created><updated>\(updated)</updated>\(tags)
        </note>
        </en-export>
        """
        return Data(xml.utf8)
    }

    private static func compactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
