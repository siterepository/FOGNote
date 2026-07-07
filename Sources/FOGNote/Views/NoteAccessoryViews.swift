import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Notebook picker

struct NotebookPicker: View {
    @Query(sort: \Notebook.name) private var notebooks: [Notebook]
    @Bindable var note: Note

    var body: some View {
        Menu {
            Button("No Notebook") { note.notebook = nil }
            Divider()
            ForEach(notebooks) { nb in
                Button {
                    note.notebook = nb
                } label: {
                    if note.notebook?.persistentModelID == nb.persistentModelID {
                        Label(nb.name, systemImage: "checkmark")
                    } else {
                        Text(nb.name)
                    }
                }
            }
        } label: {
            Label(note.notebook?.name ?? "No Notebook", systemImage: "book.closed")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}

// MARK: - Tag editor

struct TagEditorView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Bindable var note: Note
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags").font(.headline)
            HStack {
                TextField("New tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !allTags.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(allTags) { tag in
                            Toggle(isOn: binding(for: tag)) {
                                Text("#" + tag.name)
                                    .foregroundStyle(Color(hex: tag.colorHex))
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private func addTag() {
        let name = newTag.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "#", with: "")
        guard !name.isEmpty else { return }
        let tag = allTags.first { $0.name == name } ?? {
            let created = Tag(name: name)
            context.insert(created)
            return created
        }()
        if !note.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) {
            note.tags.append(tag)
        }
        newTag = ""
    }

    private func binding(for tag: Tag) -> Binding<Bool> {
        Binding(
            get: { note.tags.contains { $0.persistentModelID == tag.persistentModelID } },
            set: { include in
                if include {
                    note.tags.append(tag)
                } else {
                    note.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
                }
            }
        )
    }
}

// MARK: - Reminder editor

struct ReminderEditor: View {
    @Bindable var note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reminder").font(.headline)
            DatePicker(
                "Remind me",
                selection: Binding(
                    get: { note.reminderDate ?? .now.addingTimeInterval(3600) },
                    set: { note.reminderDate = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            Toggle("Done", isOn: $note.reminderDone)
            Button("Remove Reminder", role: .destructive) {
                note.reminderDate = nil
                note.reminderDone = false
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

// MARK: - Attachments

struct AttachmentStrip: View {
    @Environment(\.modelContext) private var context
    @Bindable var note: Note
    @State private var showImporter = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(note.attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        context.delete(attachment)
                    }
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Attach", systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let attachment = Attachment(fileName: url.lastPathComponent, contentType: type, data: data)
                attachment.note = note
                context.insert(attachment)
            }
        }
    }
}

struct AttachmentChip: View {
    let attachment: Attachment
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if attachment.contentType.hasPrefix("image/"), let image = NSImage(data: attachment.data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(Color.fogAccent)
            }
            VStack(alignment: .leading) {
                Text(attachment.fileName).font(.caption).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onTapGesture(count: 2) { open() }
        .contextMenu {
            Button("Open") { open() }
            Button("Save As…") { saveAs() }
            Button("Remove", role: .destructive, action: onDelete)
        }
        .help("Double-click to open")
    }

    private func open() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FOGNote", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: attachment.fileName)
        try? attachment.data.write(to: url)
        NSWorkspace.shared.open(url)
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? attachment.data.write(to: url)
    }
}

// MARK: - Version history

struct VersionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var note: Note
    var onRestore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Version History").font(.headline).padding()
            if note.versions.isEmpty {
                ContentUnavailableView("No Versions Yet", systemImage: "clock.arrow.circlepath",
                    description: Text("A snapshot is saved each time you open a note after edits."))
                    .frame(height: 220)
            } else {
                List(note.versions.sorted { $0.savedAt > $1.savedAt }) { version in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.callout.bold())
                            Text(version.bodyPlainText.prefix(120))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Restore") {
                            context.insert(NoteVersion(note: note))
                            note.title = version.title
                            note.bodyData = version.bodyData
                            note.bodyPlainText = version.bodyPlainText
                            note.modifiedAt = .now
                            onRestore()
                            dismiss()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 460, height: 360)
    }
}

// MARK: - Note info + links

struct NoteInfoView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var allNotes: [Note]
    let note: Note

    private var outgoingLinks: [Note] {
        let titles = Self.linkTitles(in: note.bodyPlainText)
        guard !titles.isEmpty else { return [] }
        return allNotes.filter { candidate in
            !candidate.isTrashed &&
            titles.contains { $0.caseInsensitiveCompare(candidate.title) == .orderedSame }
        }
    }

    private var backlinks: [Note] {
        guard !note.title.isEmpty else { return [] }
        let needle = "[[\(note.title.lowercased())]]"
        return allNotes.filter {
            !$0.isTrashed &&
            $0.persistentModelID != note.persistentModelID &&
            $0.bodyPlainText.lowercased().contains(needle)
        }
    }

    static func linkTitles(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note Info").font(.headline)
            Grid(alignment: .leading, verticalSpacing: 4) {
                GridRow { Text("Created").foregroundStyle(.secondary); Text(note.createdAt.formatted()) }
                GridRow { Text("Modified").foregroundStyle(.secondary); Text(note.modifiedAt.formatted()) }
                GridRow { Text("Words").foregroundStyle(.secondary); Text("\(note.wordCount)") }
                GridRow { Text("Characters").foregroundStyle(.secondary); Text("\(note.bodyPlainText.count)") }
                GridRow { Text("Attachments").foregroundStyle(.secondary); Text("\(note.attachments.count)") }
            }
            .font(.caption)

            if !outgoingLinks.isEmpty {
                Divider()
                Text("Links To").font(.caption.bold())
                linkList(outgoingLinks)
            }
            if !backlinks.isEmpty {
                Divider()
                Text("Linked From").font(.caption.bold())
                linkList(backlinks)
            }
            Text("Tip: type [[Note Title]] to link notes.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func linkList(_ notes: [Note]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(notes) { linked in
                Button {
                    appState.selectedNoteID = linked.persistentModelID
                } label: {
                    Label(linked.title.isEmpty ? "Untitled" : linked.title, systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fogAccent)
            }
        }
    }
}
