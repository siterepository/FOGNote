import SwiftUI
import SwiftData
import AppKit

struct NoteDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Bindable var note: Note

    @State private var text = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var loaded = false
    @State private var unlockPassword = ""
    @State private var unlockFailed = false
    @State private var showVersions = false
    @State private var showInfo = false
    @State private var showTagEditor = false
    @State private var showReminder = false
    @State private var showAttachmentImporter = false
    @State private var saveTask: Task<Void, Never>?
    @State private var recorder = CallRecorder()
    @State private var showRecorder = false

    var body: some View {
        Group {
            if note.isLocked && !appState.isUnlocked(note) {
                lockedView
            } else {
                editorView
            }
        }
        .toolbar { toolbarContent }
        .inspector(isPresented: $showRecorder) {
            RecordingPanel(recorder: recorder, note: note, isPresented: $showRecorder)
                .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
        }
        .onAppear {
            loadNote()
            if ProcessInfo.processInfo.arguments.contains("--uitest-recorder") {
                showRecorder = true
            }
        }
        .onDisappear { flushSave() }
    }

    // MARK: - Locked

    private var lockedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.fogLock)
            Text(note.title.isEmpty ? "Locked Note" : note.title)
                .font(.title2.bold())
            SecureField("Password", text: $unlockPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(unlock)
            if unlockFailed {
                Text("Wrong password").font(.caption).foregroundStyle(.red)
            }
            Button("Unlock", action: unlock)
                .buttonStyle(.borderedProminent)
                .tint(Color.fogAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlock() {
        if LockService.verify(password: unlockPassword, note: note) {
            appState.unlockedNoteIDs.insert(note.persistentModelID)
            unlockFailed = false
            loadNote()
        } else {
            unlockFailed = true
        }
        unlockPassword = ""
    }

    // MARK: - Editor

    private var editorView: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $note.title, prompt: Text("Title"))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .onChange(of: note.title) { note.modifiedAt = .now }

            metadataBar
                .padding(.horizontal, 20)
                .padding(.vertical, 6)

            EditorToolbar(text: $text, selection: $selection, onChecklist: toggleChecklist)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            Divider()

            TextEditor(text: $text, selection: $selection)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .onChange(of: text) { scheduleSave() }

            if !note.recordings.isEmpty {
                Divider()
                ScrollView {
                    RecordingsSection(note: note)
                }
                .frame(maxHeight: 260)
            }

            if !note.attachments.isEmpty {
                Divider()
                AttachmentStrip(note: note)
            }

            Divider()
            footer
        }
        .background(.background)
    }

    private var metadataBar: some View {
        HStack(spacing: 12) {
            NotebookPicker(note: note)
            Button {
                showTagEditor.toggle()
            } label: {
                if note.tags.isEmpty {
                    Label("Add Tags", systemImage: "tag")
                } else {
                    Label(note.tags.map { "#" + $0.name }.joined(separator: " "), systemImage: "tag")
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.fogAccent)
            .popover(isPresented: $showTagEditor) { TagEditorView(note: note) }

            if let reminder = note.reminderDate {
                Button {
                    showReminder.toggle()
                } label: {
                    Label(reminder.noteListLabel, systemImage: note.reminderDone ? "bell.slash" : "bell.badge")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(note.reminderDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.fogWarn))
                .popover(isPresented: $showReminder) { ReminderEditor(note: note) }
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Text("Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Spacer()
            Text("\(wordCount) words")
            Spacer()
            Text("Edited \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    private var wordCount: Int {
        String(text.characters).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showRecorder = true
            } label: {
                Label("Record", systemImage: recorder.isActive ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(recorder.isActive ? Color(hex: "#E5484D") : Color.primary)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Record a call into this note (⌘⇧R)")

            Button {
                note.isPinned.toggle()
            } label: {
                Label("Pin", systemImage: note.isPinned ? "pin.fill" : "pin")
            }
            .help(note.isPinned ? "Unpin" : "Pin")

            Button {
                showReminder.toggle()
                if note.reminderDate == nil { note.reminderDate = .now.addingTimeInterval(3600) }
            } label: {
                Label("Reminder", systemImage: "bell.badge")
            }
            .help("Set a reminder")
            .popover(isPresented: $showReminder) { ReminderEditor(note: note) }

            lockMenu

            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.rawValue) {
                        flushSave()
                        ExportService.export(note: note, format: format)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export note")

            Button {
                flushSave()
                showVersions = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .help("Version history")
            .sheet(isPresented: $showVersions) {
                VersionHistoryView(note: note, onRestore: { loadNote() })
            }

            Button {
                showInfo.toggle()
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            .help("Note info and links")
            .popover(isPresented: $showInfo) { NoteInfoView(note: note) }

            Button {
                note.isTrashed = true
                note.trashedAt = .now
                appState.selectedNoteID = nil
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Move to Trash")
        }
    }

    private var lockMenu: some View {
        Menu {
            if note.isLocked {
                Button("Remove Lock") {
                    if promptPassword(verifyAgainst: note) {
                        LockService.removeLock(from: note)
                        appState.unlockedNoteIDs.remove(note.persistentModelID)
                    }
                }
                Button("Lock Now") {
                    flushSave()
                    appState.unlockedNoteIDs.remove(note.persistentModelID)
                }
            } else {
                Button("Set Password Lock…") {
                    if let password = promptNewPassword() {
                        LockService.setLock(on: note, password: password)
                        appState.unlockedNoteIDs.insert(note.persistentModelID)
                    }
                }
            }
        } label: {
            Label("Lock", systemImage: note.isLocked ? "lock.fill" : "lock")
        }
        .help("Password protection")
    }

    // MARK: - Persistence

    private func loadNote() {
        guard !note.isLocked || appState.isUnlocked(note) else { return }
        text = AttributedString(rtfData: note.bodyData)
        if String(text.characters).isEmpty && !note.bodyPlainText.isEmpty {
            text = AttributedString(note.bodyPlainText)
        }
        if !loaded {
            snapshotVersionIfNeeded()
            loaded = true
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        persist()
    }

    private func persist() {
        let plain = String(text.characters)
        guard plain != note.bodyPlainText || note.bodyData.isEmpty else { return }
        note.bodyData = text.rtfData()
        note.bodyPlainText = plain
        note.modifiedAt = .now
        try? context.save()
    }

    private func snapshotVersionIfNeeded() {
        guard !note.bodyPlainText.isEmpty else { return }
        let last = note.versions.sorted { $0.savedAt > $1.savedAt }.first
        guard last?.bodyPlainText != note.bodyPlainText else { return }
        context.insert(NoteVersion(note: note))
        let versions = note.versions.sorted { $0.savedAt > $1.savedAt }
        for old in versions.dropFirst(20) { context.delete(old) }
    }

    // MARK: - Checklist

    private func toggleChecklist() {
        let plain = String(text.characters)
        guard !plain.isEmpty || true else { return }
        let offsets = selectedLineStartOffsets(in: plain)
        for offset in offsets.sorted(by: >) {
            toggleCheckbox(atLineStart: offset)
        }
    }

    private func selectedLineStartOffsets(in plain: String) -> [Int] {
        let indices = selection.indices(in: text)
        var startOffset = 0
        var endOffset = 0
        switch indices {
        case .insertionPoint(let index):
            startOffset = text.characters.distance(from: text.startIndex, to: index)
            endOffset = startOffset
        case .ranges(let rangeSet):
            guard let first = rangeSet.ranges.first, let last = rangeSet.ranges.last else { return [] }
            startOffset = text.characters.distance(from: text.startIndex, to: first.lowerBound)
            endOffset = text.characters.distance(from: text.startIndex, to: last.upperBound)
        }
        let chars = Array(plain)
        var lineStarts: [Int] = []
        var lineStart = 0
        for i in 0...chars.count {
            let isEnd = i == chars.count || chars[i] == "\n"
            if isEnd {
                if lineStart <= endOffset && i >= startOffset {
                    lineStarts.append(lineStart)
                }
                lineStart = i + 1
            }
        }
        if lineStarts.isEmpty { lineStarts = [0] }
        return lineStarts
    }

    private func toggleCheckbox(atLineStart offset: Int) {
        let chars = text.characters
        guard offset <= chars.count else { return }
        let lineStart = chars.index(text.startIndex, offsetBy: offset)
        let plain = String(chars)
        let charArray = Array(plain)

        let hasBox = offset + 1 < charArray.count && (charArray[offset] == "☐" || charArray[offset] == "☑") && charArray[offset + 1] == " "
        if hasBox {
            let two = chars.index(lineStart, offsetBy: 2)
            let symbol = charArray[offset]
            if symbol == "☐" {
                text.characters.replaceSubrange(lineStart..<two, with: "☑ ")
            } else {
                text.characters.removeSubrange(lineStart..<two)
            }
        } else {
            text.characters.insert(contentsOf: "☐ ", at: lineStart)
        }
        selection = AttributedTextSelection()
        scheduleSave()
    }

    // MARK: - Password prompts (NSAlert for reliable secure input)

    private func promptNewPassword() -> String? {
        let alert = NSAlert()
        alert.messageText = "Set Note Password"
        alert.informativeText = "This note will require the password to open. There is no recovery if forgotten."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Set Password")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    private func promptPassword(verifyAgainst note: Note) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Enter Note Password"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return LockService.verify(password: field.stringValue, note: note)
    }
}
