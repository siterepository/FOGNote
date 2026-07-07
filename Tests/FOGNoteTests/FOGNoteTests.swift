import Testing
import Foundation
@testable import FOGNote

@MainActor @Suite struct SearchServiceTests {
    private func makeNote(title: String, body: String, tags: [FOGNote.Tag] = [], notebook: Notebook? = nil) -> Note {
        let note = Note(title: title, notebook: notebook)
        note.bodyPlainText = body
        note.tags = tags
        return note
    }

    @Test func freeTextMatchesTitleAndBody() {
        let a = makeNote(title: "Groceries", body: "milk eggs")
        let b = makeNote(title: "Work", body: "quarterly plan")
        let result = SearchService.filter(notes: [a, b], query: "milk")
        #expect(result.count == 1 && result[0].title == "Groceries")
    }

    @Test func tagFilter() {
        let tag = FOGNote.Tag(name: "urgent")
        let a = makeNote(title: "A", body: "", tags: [tag])
        let b = makeNote(title: "B", body: "")
        let result = SearchService.filter(notes: [a, b], query: "tag:urgent")
        #expect(result.count == 1 && result[0].title == "A")
    }

    @Test func intitleFilter() {
        let a = makeNote(title: "Roadmap 2026", body: "")
        let b = makeNote(title: "Notes", body: "roadmap mention")
        let result = SearchService.filter(notes: [a, b], query: "intitle:roadmap")
        #expect(result.count == 1 && result[0].title == "Roadmap 2026")
    }

    @Test func todoFilter() {
        let a = makeNote(title: "Tasks", body: "☐ buy milk")
        let b = makeNote(title: "Plain", body: "nothing here")
        let result = SearchService.filter(notes: [a, b], query: "todo:true")
        #expect(result.count == 1 && result[0].title == "Tasks")
    }
}

@MainActor @Suite struct LockServiceTests {
    @Test func lockRoundTrip() {
        let note = Note(title: "Secret")
        LockService.setLock(on: note, password: "hunter2")
        #expect(note.isLocked)
        #expect(LockService.verify(password: "hunter2", note: note))
        #expect(!LockService.verify(password: "wrong", note: note))
        LockService.removeLock(from: note)
        #expect(!note.isLocked && note.lockPasswordHash == nil)
    }
}

@MainActor @Suite struct ExportTests {
    @Test func markdownChecklistConversion() {
        let note = Note(title: "List")
        note.bodyPlainText = "☐ one\n☑ two"
        let md = ExportService.markdown(for: note)
        #expect(md.contains("- [ ] one"))
        #expect(md.contains("- [x] two"))
    }
}

@MainActor @Suite struct LinkParsingTests {
    @Test func extractsWikiLinks() {
        let titles = NoteInfoView.linkTitles(in: "see [[Roadmap]] and [[Meeting Notes]] ok")
        #expect(titles == ["Roadmap", "Meeting Notes"])
    }
}
