import Foundation
import SwiftData
import AppKit

@MainActor
enum SeedData {
    static func seedIfNeeded(container: ModelContainer) {
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<Note>())) ?? 0
        guard count == 0 else { return }

        let personal = Notebook(name: "Personal")
        let work = Notebook(name: "Work")
        context.insert(personal)
        context.insert(work)

        let welcome = Note(title: "Welcome to FOGNote", notebook: personal)
        welcome.isPinned = true
        setBody(welcome, """
        Welcome to FOGNote — Evernote and Apple Notes, merged.

        Highlights:
        • Notebooks, stacks, and nested tags in the sidebar
        • Rich text: bold, italic, underline, colors, sizes (toolbar above)
        • Checklists: ⌘⇧L turns the current line into a to-do
        • Pin, lock, template, and reminder from the note toolbar
        • Link notes by typing [[Note Title]]
        • Saved searches: run a search, then click the bookmark icon
        • Export notes as Markdown, HTML, PDF, or ENEX
        • Everything is stored locally on your Mac

        Make this note yours, or press ⌘N to start fresh.
        """)
        context.insert(welcome)

        let meeting = Note(title: "Meeting Notes", notebook: work)
        meeting.isTemplate = true
        setBody(meeting, """
        Date:\u{20}
        Attendees:\u{20}

        Agenda
        ☐ Item one
        ☐ Item two

        Decisions

        Action Items
        ☐\u{20}
        """)
        context.insert(meeting)

        let daily = Note(title: "Daily Journal", notebook: personal)
        daily.isTemplate = true
        setBody(daily, """
        Morning intentions
        ☐\u{20}

        Highlights

        Gratitude
        """)
        context.insert(daily)

        let ideas = Tag(name: "ideas")
        let urgent = Tag(name: "urgent", colorHex: "#F59E0B")
        context.insert(ideas)
        context.insert(urgent)

        try? context.save()
    }

    private static func setBody(_ note: Note, _ text: String) {
        var attr = AttributedString(text)
        attr.font = .system(size: 14)
        note.bodyData = attr.rtfData()
        note.bodyPlainText = text
    }
}
