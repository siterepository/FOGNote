import Foundation
import SwiftData

// MARK: - Note

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    /// RTF-encoded rich text body (AttributedString round-trips through RTF).
    var bodyData: Data = Data()
    /// Plain-text mirror of the body, kept in sync for search/preview.
    var bodyPlainText: String = ""
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now
    var isPinned: Bool = false
    var isLocked: Bool = false
    /// SHA-256 hash of the note password when locked (salted with note id).
    var lockPasswordHash: Data?
    var isTrashed: Bool = false
    var trashedAt: Date?
    var isTemplate: Bool = false
    var reminderDate: Date?
    var reminderDone: Bool = false
    var sourceURL: String?

    var notebook: Notebook?
    @Relationship(inverse: \Tag.notes) var tags: [Tag] = []
    @Relationship(deleteRule: .cascade, inverse: \Attachment.note) var attachments: [Attachment] = []
    @Relationship(deleteRule: .cascade, inverse: \NoteVersion.note) var versions: [NoteVersion] = []
    @Relationship(deleteRule: .cascade, inverse: \Recording.note) var recordings: [Recording] = []

    init(title: String = "", notebook: Notebook? = nil) {
        self.title = title
        self.notebook = notebook
    }

    var previewText: String {
        let text = bodyPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(300))
    }

    var wordCount: Int {
        bodyPlainText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

// MARK: - Notebook & Stack

@Model
final class Notebook {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var sortOrder: Int = 0
    var stack: Stack?
    @Relationship(deleteRule: .nullify, inverse: \Note.notebook) var notes: [Note] = []

    init(name: String, stack: Stack? = nil) {
        self.name = name
        self.stack = stack
    }
}

@Model
final class Stack {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Notebook.stack) var notebooks: [Notebook] = []

    init(name: String) {
        self.name = name
    }
}

// MARK: - Tag

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#6B9FD4"
    var notes: [Note] = []

    init(name: String, colorHex: String = "#6B9FD4") {
        self.name = name
        self.colorHex = colorHex
    }
}

// MARK: - Attachment

@Model
final class Attachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var contentType: String = ""
    @Attribute(.externalStorage) var data: Data = Data()
    var createdAt: Date = Date.now
    /// Text recognized inside image attachments (Vision OCR); searchable.
    var ocrText: String = ""
    var note: Note?

    init(fileName: String, contentType: String, data: Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }
}

// MARK: - Version history

@Model
final class NoteVersion {
    var id: UUID = UUID()
    var savedAt: Date = Date.now
    var title: String = ""
    var bodyData: Data = Data()
    var bodyPlainText: String = ""
    var note: Note?

    init(note: Note) {
        self.savedAt = .now
        self.title = note.title
        self.bodyData = note.bodyData
        self.bodyPlainText = note.bodyPlainText
        self.note = note
    }
}

// MARK: - Snippet (text expansion / objection responses)

@Model
final class Snippet {
    var id: UUID = UUID()
    var name: String = ""
    var content: String = ""
    var category: String = "General"
    var createdAt: Date = Date.now

    init(name: String, content: String, category: String = "General") {
        self.name = name
        self.content = content
        self.category = category
    }
}

// MARK: - Saved search

@Model
final class SavedSearch {
    var id: UUID = UUID()
    var name: String = ""
    var query: String = ""
    var createdAt: Date = Date.now

    init(name: String, query: String) {
        self.name = name
        self.query = query
    }
}
