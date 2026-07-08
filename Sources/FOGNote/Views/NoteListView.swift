import SwiftUI
import SwiftData

enum NoteSortOrder: String, CaseIterable {
    case modified = "Date Edited"
    case created = "Date Created"
    case title = "Title"
}

struct NoteListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

    @Query private var allNotes: [Note]
    @AppStorage("noteSortOrder") private var sortOrder: NoteSortOrder = .modified
    @State private var showSaveSearch = false
    @State private var savedSearchName = ""
    @State private var showHub = false

    var body: some View {
        @Bindable var appState = appState
        let notes = filteredNotes()
        List(selection: $appState.selectedNoteID) {
            ForEach(notes) { note in
                NoteRowView(note: note)
                    .tag(note.persistentModelID)
                    .contextMenu { noteContextMenu(note) }
            }
        }
        .listStyle(.inset)
        .navigationTitle(listTitle)
        .navigationSubtitle("\(notes.count) note\(notes.count == 1 ? "" : "s")")
        .toolbar {
            ToolbarItemGroup {
                if isHubEligible {
                    Button {
                        showHub = true
                    } label: {
                        Label("Prospect Hub", systemImage: "person.crop.square.filled.and.at.rectangle")
                    }
                    .help("Activity timeline, open action items, and deal-sheet export")
                    .sheet(isPresented: $showHub) {
                        ProspectHubView(title: listTitle, notes: notes)
                    }
                }
                if !appState.searchText.isEmpty {
                    Button {
                        savedSearchName = appState.searchText
                        showSaveSearch = true
                    } label: {
                        Label("Save Search", systemImage: "bookmark")
                    }
                    .help("Save this search to the sidebar")
                }
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(NoteSortOrder.allCases, id: \.self) { Text($0.rawValue) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                Button {
                    createNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Note (⌘N)")
            }
        }
        .alert("Save Search", isPresented: $showSaveSearch) {
            TextField("Name", text: $savedSearchName)
            Button("Save") {
                if !savedSearchName.isEmpty {
                    context.insert(SavedSearch(name: savedSearchName, query: appState.searchText))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if appState.selectedNoteID == nil {
                appState.selectedNoteID = notes.first?.persistentModelID
            }
        }
        .onChange(of: appState.requestNewNote) { _, wants in
            if wants {
                appState.requestNewNote = false
                createNote()
            }
        }
    }

    private var isHubEligible: Bool {
        switch appState.sidebarSelection {
        case .notebook, .stack, .tag: true
        default: false
        }
    }

    // MARK: - Filtering

    private func filteredNotes() -> [Note] {
        var notes: [Note]
        var query = appState.searchText

        switch appState.sidebarSelection {
        case .trash:
            notes = allNotes.filter(\.isTrashed)
        case .templates:
            notes = allNotes.filter { $0.isTemplate && !$0.isTrashed }
        case .pinned:
            notes = allNotes.filter { $0.isPinned && !$0.isTrashed && !$0.isTemplate }
        case .tasks:
            notes = allNotes.filter {
                !$0.isTrashed && !$0.isTemplate &&
                ($0.reminderDate != nil || $0.bodyPlainText.contains("☐"))
            }
        case .notebook(let id):
            notes = allNotes.filter { $0.notebook?.persistentModelID == id && !$0.isTrashed && !$0.isTemplate }
        case .stack(let id):
            notes = allNotes.filter { $0.notebook?.stack?.persistentModelID == id && !$0.isTrashed && !$0.isTemplate }
        case .tag(let id):
            notes = allNotes.filter { note in
                !note.isTrashed && !note.isTemplate &&
                note.tags.contains { $0.persistentModelID == id }
            }
        case .savedSearch(let id):
            if let saved = context.registeredModel(for: id) as SavedSearch? {
                query = saved.query
            }
            notes = allNotes.filter { !$0.isTrashed && !$0.isTemplate }
        case .allNotes, .recordings, nil:
            notes = allNotes.filter { !$0.isTrashed && !$0.isTemplate }
        }

        if !query.isEmpty {
            notes = SearchService.filter(notes: notes, query: query)
        }

        return notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            switch sortOrder {
            case .modified: return a.modifiedAt > b.modifiedAt
            case .created: return a.createdAt > b.createdAt
            case .title: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    private var listTitle: String {
        switch appState.sidebarSelection {
        case .allNotes, .recordings, nil: "All Notes"
        case .pinned: "Pinned"
        case .tasks: "Tasks"
        case .templates: "Templates"
        case .trash: "Trash"
        case .notebook(let id): (context.registeredModel(for: id) as Notebook?)?.name ?? "Notebook"
        case .stack(let id): (context.registeredModel(for: id) as Stack?)?.name ?? "Stack"
        case .tag(let id): "#" + ((context.registeredModel(for: id) as Tag?)?.name ?? "tag")
        case .savedSearch(let id): (context.registeredModel(for: id) as SavedSearch?)?.name ?? "Search"
        }
    }

    // MARK: - Actions

    private func createNote() {
        let notebook: Notebook? = {
            if case .notebook(let id) = appState.sidebarSelection {
                return context.registeredModel(for: id) as Notebook?
            }
            return nil
        }()
        let note = Note(title: "", notebook: notebook)
        if case .templates = appState.sidebarSelection { note.isTemplate = true }
        context.insert(note)
        try? context.save()
        appState.selectedNoteID = note.persistentModelID
    }

    @ViewBuilder
    private func noteContextMenu(_ note: Note) -> some View {
        if note.isTrashed {
            Button("Restore") {
                note.isTrashed = false
                note.trashedAt = nil
            }
            Button("Delete Permanently", role: .destructive) {
                if appState.selectedNoteID == note.persistentModelID { appState.selectedNoteID = nil }
                context.delete(note)
            }
        } else {
            Button(note.isPinned ? "Unpin" : "Pin") { note.isPinned.toggle() }
            Button("Duplicate") { duplicate(note) }
            if note.isTemplate {
                Button("New Note from Template") { instantiateTemplate(note) }
            } else {
                Button("Save as Template") {
                    let copy = duplicate(note, select: false)
                    copy.isTemplate = true
                    copy.isPinned = false
                }
            }
            Menu("Move to Notebook") {
                MoveToNotebookMenu(note: note)
            }
            Button("Move to Trash", role: .destructive) {
                note.isTrashed = true
                note.trashedAt = .now
                if appState.selectedNoteID == note.persistentModelID { appState.selectedNoteID = nil }
            }
        }
    }

    @discardableResult
    private func duplicate(_ note: Note, select: Bool = true) -> Note {
        let copy = Note(title: note.title.isEmpty ? "Copy" : note.title + " Copy", notebook: note.notebook)
        copy.bodyData = note.bodyData
        copy.bodyPlainText = note.bodyPlainText
        copy.tags = note.tags
        context.insert(copy)
        if select { appState.selectedNoteID = copy.persistentModelID }
        return copy
    }

    private func instantiateTemplate(_ template: Note) {
        let note = TemplateEngine.instantiate(template: template, into: context)
        appState.sidebarSelection = .allNotes
        appState.selectedNoteID = note.persistentModelID
    }
}

struct MoveToNotebookMenu: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Notebook.name) private var notebooks: [Notebook]
    let note: Note

    var body: some View {
        Button("None") { note.notebook = nil }
        ForEach(notebooks) { nb in
            Button(nb.name) { note.notebook = nb }
        }
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.fogAccent)
                }
                if note.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.fogLock)
                }
                if note.isTemplate {
                    Image(systemName: "doc.text.image")
                        .font(.caption2)
                        .foregroundStyle(Color.fogSecondary)
                }
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Text(note.isLocked ? "Locked note" : (note.previewText.isEmpty ? "No additional text" : note.previewText))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(note.modifiedAt.noteListLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if let reminder = note.reminderDate {
                    Label(reminder.noteListLabel, systemImage: "bell.badge")
                        .font(.system(size: 10))
                        .foregroundStyle(note.reminderDone ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.fogWarn))
                }
                if let nb = note.notebook {
                    Label(nb.name, systemImage: "book.closed")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                ForEach(note.tags.prefix(3)) { tag in
                    Text("#\(tag.name)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: tag.colorHex))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
