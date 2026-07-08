import Foundation
import AppKit
import SwiftData

/// Template variables ({{date}}, {{time}}, {{clipboard}}, …) and daily notes.
@MainActor
enum TemplateEngine {
    static func expand(_ text: String) -> String {
        var out = text
        let now = Date.now
        let replacements: [String: String] = [
            "{{date}}": now.formatted(date: .complete, time: .omitted),
            "{{shortdate}}": now.formatted(date: .abbreviated, time: .omitted),
            "{{time}}": now.formatted(date: .omitted, time: .shortened),
            "{{weekday}}": now.formatted(.dateTime.weekday(.wide)),
            "{{clipboard}}": NSPasteboard.general.string(forType: .string) ?? "",
        ]
        for (token, value) in replacements {
            out = out.replacingOccurrences(of: token, with: value, options: .caseInsensitive)
        }
        return out
    }

    static func instantiate(template: Note, into context: ModelContext) -> Note {
        let note = Note(title: expand(template.title), notebook: template.notebook)
        let expanded = expand(template.bodyPlainText)
        var attr = AttributedString(expanded)
        attr.font = .system(size: 14)
        note.bodyData = attr.rtfData()
        note.bodyPlainText = expanded
        note.tags = template.tags
        context.insert(note)
        return note
    }

    /// Today's daily note — created from the "Daily Journal" template (or a
    /// built-in fallback) the first time each day, reused after that.
    static func dailyNote(context: ModelContext) -> Note {
        let todayTitle = "Daily — \(Date.now.formatted(date: .abbreviated, time: .omitted))"
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        if let existing = notes.first(where: { $0.title == todayTitle && !$0.isTrashed }) {
            return existing
        }
        let body: String
        if let template = notes.first(where: { $0.isTemplate && $0.title.localizedCaseInsensitiveContains("daily") }) {
            body = expand(template.bodyPlainText)
        } else {
            body = expand("""
            {{weekday}}, {{shortdate}}

            Top priorities
            ☐\u{20}

            Calls & follow-ups
            ☐\u{20}

            Notes
            """)
        }
        let note = Note(title: todayTitle)
        var attr = AttributedString(body)
        attr.font = .system(size: 14)
        note.bodyData = attr.rtfData()
        note.bodyPlainText = body
        note.isPinned = true
        context.insert(note)
        try? context.save()
        return note
    }
}
