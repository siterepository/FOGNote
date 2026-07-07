import Foundation
import SwiftData
import AppKit

/// Imports Markdown, plain text, RTF, HTML, and Evernote ENEX files.
@MainActor
enum ImportService {
    static func runImportPanel(context: ModelContext) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .rtf, .html, .xml, .init(filenameExtension: "md")!, .init(filenameExtension: "enex")!].compactMap { $0 }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            importFile(at: url, context: context)
        }
        try? context.save()
    }

    static func importFile(at url: URL, context: ModelContext) {
        switch url.pathExtension.lowercased() {
        case "enex":
            importENEX(at: url, context: context)
        case "rtf":
            if let data = try? Data(contentsOf: url) {
                let attr = AttributedString(rtfData: data)
                insertNote(title: url.deletingPathExtension().lastPathComponent,
                           body: attr, context: context)
            }
        case "html", "htm":
            if let data = try? Data(contentsOf: url),
               let ns = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                insertNote(title: url.deletingPathExtension().lastPathComponent,
                           body: AttributedString(ns), context: context)
            }
        default: // md, txt
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                var title = url.deletingPathExtension().lastPathComponent
                var body = text
                if body.hasPrefix("# "), let firstLine = body.split(separator: "\n", maxSplits: 1).first {
                    title = String(firstLine.dropFirst(2))
                    body = String(body.dropFirst(firstLine.count)).trimmingCharacters(in: .newlines)
                }
                body = body.replacingOccurrences(of: "- [ ] ", with: "☐ ")
                    .replacingOccurrences(of: "- [x] ", with: "☑ ")
                var attr = AttributedString(body)
                attr.font = .system(size: 14)
                insertNote(title: title, body: attr, context: context)
            }
        }
    }

    private static func insertNote(title: String, body: AttributedString, context: ModelContext) {
        let note = Note(title: title)
        note.bodyData = body.rtfData()
        note.bodyPlainText = body.plainText
        context.insert(note)
    }

    // MARK: - ENEX

    private static func importENEX(at url: URL, context: ModelContext) {
        guard let data = try? Data(contentsOf: url) else { return }
        let parser = ENEXParser()
        for parsed in parser.parse(data: data) {
            let note = Note(title: parsed.title)
            var attr = AttributedString(parsed.plainText)
            attr.font = .system(size: 14)
            note.bodyData = attr.rtfData()
            note.bodyPlainText = parsed.plainText
            if let created = parsed.created { note.createdAt = created }
            for tagName in parsed.tags {
                let existing = try? context.fetch(FetchDescriptor<Tag>()).first { $0.name == tagName }
                let tag = existing ?? Tag(name: tagName)
                if existing == nil { context.insert(tag) }
                note.tags.append(tag)
            }
            context.insert(note)
        }
    }
}

struct ENEXNote {
    var title = ""
    var plainText = ""
    var created: Date?
    var tags: [String] = []
}

final class ENEXParser: NSObject, XMLParserDelegate {
    private var notes: [ENEXNote] = []
    private var current: ENEXNote?
    private var element = ""
    private var buffer = ""

    func parse(data: Data) -> [ENEXNote] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return notes
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        element = name
        buffer = ""
        if name == "note" { current = ENEXNote() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        buffer += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        switch name {
        case "title":
            current?.title = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        case "content":
            current?.plainText = Self.stripENML(buffer)
        case "created":
            current?.created = Self.parseDate(buffer)
        case "tag":
            current?.tags.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        case "note":
            if let note = current { notes.append(note) }
            current = nil
        default:
            break
        }
    }

    private static func stripENML(_ enml: String) -> String {
        var text = enml
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<en-todo[^>]*checked=\"true\"[^>]*/?>", with: "☑ ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<en-todo[^>]*/?>", with: "☐ ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
