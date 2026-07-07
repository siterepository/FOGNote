import Foundation

/// Evernote-style search grammar: free text plus `tag:name`, `notebook:name`,
/// `intitle:word`, `created:>2026-01-01`, `todo:true`.
enum SearchService {
    static func filter(notes: [Note], query: String) -> [Note] {
        let tokens = tokenize(query)
        return notes.filter { note in
            tokens.allSatisfy { matches(note: note, token: $0) }
        }
    }

    private static func tokenize(_ query: String) -> [String] {
        query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    private static func matches(note: Note, token: String) -> Bool {
        let lower = token.lowercased()
        if let value = value(of: "tag:", in: lower) {
            return note.tags.contains { $0.name.lowercased().contains(value) }
        }
        if let value = value(of: "notebook:", in: lower) {
            return note.notebook?.name.lowercased().contains(value) ?? false
        }
        if let value = value(of: "intitle:", in: lower) {
            return note.title.lowercased().contains(value)
        }
        if let value = value(of: "todo:", in: lower) {
            let hasTodo = note.bodyPlainText.contains("☐") || note.bodyPlainText.contains("☑")
            return value == "true" ? hasTodo : !hasTodo
        }
        if let value = value(of: "created:>", in: lower), let date = parseDate(value) {
            return note.createdAt > date
        }
        if let value = value(of: "created:<", in: lower), let date = parseDate(value) {
            return note.createdAt < date
        }
        return note.title.lowercased().contains(lower)
            || note.bodyPlainText.lowercased().contains(lower)
            || note.tags.contains { $0.name.lowercased().contains(lower) }
    }

    private static func value(of prefix: String, in token: String) -> String? {
        guard token.hasPrefix(prefix) else { return nil }
        let value = String(token.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
