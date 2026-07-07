import SwiftUI
import SwiftData
import AppKit

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

    @Query(sort: \Stack.sortOrder) private var stacks: [Stack]
    @Query(sort: \Notebook.name) private var notebooks: [Notebook]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \SavedSearch.name) private var savedSearches: [SavedSearch]

    @State private var showNewNotebook = false
    @State private var showNewStack = false
    @State private var newItemName = ""

    private var looseNotebooks: [Notebook] {
        notebooks.filter { $0.stack == nil }
    }

    var body: some View {
        @Bindable var appState = appState
        List(selection: $appState.sidebarSelection) {
            Section {
                Label("All Notes", systemImage: "note.text").tag(SidebarItem.allNotes)
                Label("Pinned", systemImage: "pin").tag(SidebarItem.pinned)
                Label("Tasks", systemImage: "checkmark.circle").tag(SidebarItem.tasks)
                Label("Templates", systemImage: "doc.text.image").tag(SidebarItem.templates)
            }

            Section("Notebooks") {
                ForEach(stacks) { stack in
                    DisclosureGroup {
                        ForEach(stack.notebooks.sorted { $0.name < $1.name }) { nb in
                            notebookRow(nb)
                        }
                    } label: {
                        Label(stack.name, systemImage: "folder.circle")
                            .tag(SidebarItem.stack(stack.persistentModelID))
                            .contextMenu {
                                Button("Rename Stack") { rename(stack: stack) }
                                Button("Delete Stack", role: .destructive) { context.delete(stack) }
                            }
                    }
                }
                ForEach(looseNotebooks) { nb in
                    notebookRow(nb)
                }
            }

            Section("Tags") {
                ForEach(tags) { tag in
                    Label {
                        Text(tag.name)
                    } icon: {
                        Image(systemName: "tag")
                            .foregroundStyle(Color(hex: tag.colorHex))
                    }
                    .tag(SidebarItem.tag(tag.persistentModelID))
                    .contextMenu {
                        Button("Delete Tag", role: .destructive) { context.delete(tag) }
                    }
                }
            }

            if !savedSearches.isEmpty {
                Section("Saved Searches") {
                    ForEach(savedSearches) { search in
                        Label(search.name, systemImage: "magnifyingglass.circle")
                            .tag(SidebarItem.savedSearch(search.persistentModelID))
                            .contextMenu {
                                Button("Delete Saved Search", role: .destructive) { context.delete(search) }
                            }
                    }
                }
            }

            Section {
                Label("Trash", systemImage: "trash").tag(SidebarItem.trash)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("FOGNote")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("New Notebook") { showNewNotebook = true }
                    Button("New Stack") { showNewStack = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .alert("New Notebook", isPresented: $showNewNotebook) {
            TextField("Name", text: $newItemName)
            Button("Create") {
                if !newItemName.isEmpty { context.insert(Notebook(name: newItemName)) }
                newItemName = ""
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        }
        .alert("New Stack", isPresented: $showNewStack) {
            TextField("Name", text: $newItemName)
            Button("Create") {
                if !newItemName.isEmpty { context.insert(Stack(name: newItemName)) }
                newItemName = ""
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        }
    }

    @ViewBuilder
    private func notebookRow(_ nb: Notebook) -> some View {
        Label(nb.name, systemImage: "book.closed")
            .tag(SidebarItem.notebook(nb.persistentModelID))
            .badge(nb.notes.filter { !$0.isTrashed && !$0.isTemplate }.count)
            .contextMenu {
                Menu("Move to Stack") {
                    Button("None") { nb.stack = nil }
                    ForEach(stacks) { stack in
                        Button(stack.name) { nb.stack = stack }
                    }
                }
                Button("Rename Notebook") { rename(notebook: nb) }
                Button("Delete Notebook", role: .destructive) {
                    for note in nb.notes { note.isTrashed = true; note.trashedAt = .now }
                    context.delete(nb)
                }
            }
    }

    private func rename(notebook: Notebook) {
        promptRename(current: notebook.name) { notebook.name = $0 }
    }

    private func rename(stack: Stack) {
        promptRename(current: stack.name) { stack.name = $0 }
    }

    private func promptRename(current: String, apply: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        let field = NSTextField(string: current)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
            apply(field.stringValue)
        }
    }
}
