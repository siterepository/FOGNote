import SwiftUI
import SwiftData

struct FOGNoteCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { appState.requestNewNote = true }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            DailyNoteCommand(appState: appState)
            ImportCommand()
        }
        CommandGroup(replacing: .appInfo) {
            AboutCommand()
        }
        CommandMenu("Sales") {
            OpenWindowCommand(title: "Insights", id: "insights", key: "1")
            OpenWindowCommand(title: "Sales Library", id: "library", key: "2")
            OpenWindowCommand(title: "Note Graph", id: "graph", key: "3")
        }
    }
}

private struct OpenWindowCommand: View {
    @Environment(\.openWindow) private var openWindow
    let title: String
    let id: String
    let key: KeyEquivalent

    init(title: String, id: String, key: Character) {
        self.title = title
        self.id = id
        self.key = KeyEquivalent(key)
    }

    var body: some View {
        Button(title) { openWindow(id: id) }
            .keyboardShortcut(key, modifiers: [.command, .option])
    }
}

private struct DailyNoteCommand: View {
    @Environment(\.modelContext) private var context
    let appState: AppState

    var body: some View {
        Button("Today's Daily Note") {
            let note = TemplateEngine.dailyNote(context: context)
            appState.sidebarSelection = .allNotes
            appState.selectedNoteID = note.persistentModelID
        }
        .keyboardShortcut("d", modifiers: .command)
    }
}

private struct ImportCommand: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        Button("Import Notes… (MD, TXT, RTF, HTML, ENEX)") {
            ImportService.runImportPanel(context: context)
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
    }
}

private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About FOGNote") { openWindow(id: "about") }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            Text("FOGNote").font(.system(size: 26, weight: .bold))
            Text("Evernote × Apple Notes, merged.")
                .foregroundStyle(Color.fogAccent)
            Text("Version 1.1.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().frame(width: 200)
            Text("Local-first notes, call recording, on-device transcription\nand AI sales summaries. Nothing leaves your Mac.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("© 2026 FOG")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 340)
    }
}

struct SettingsView: View {
    @AppStorage("noteSortOrder") private var sortOrder: NoteSortOrder = .modified
    @AppStorage("trashRetentionDays") private var trashRetentionDays = 30
    @AppStorage("autoSummarize") private var autoSummarize = true

    var body: some View {
        Form {
            Picker("Default sort order", selection: $sortOrder) {
                ForEach(NoteSortOrder.allCases, id: \.self) { Text($0.rawValue) }
            }
            Stepper("Empty trash after \(trashRetentionDays) days", value: $trashRetentionDays, in: 1...365)
            Toggle("Auto-summarize recordings with on-device AI", isOn: $autoSummarize)
            if case .unavailable(let reason) = SummaryService.availability() {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Data location") {
                Text("~/Library/Application Support/FOGNote")
                    .textSelection(.enabled)
            }
            Section("Encrypted Backup") {
                HStack {
                    Button("Back Up Now…") { runBackup() }
                    Button("Restore from Backup…") { runRestore() }
                }
                Text("AES-256 encrypted archive of all notes, recordings, and transcripts. Restore replaces current data (a safety copy is kept) and relaunches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func promptPassword(_ title: String, informative: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informative
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    private func runBackup() {
        guard let password = promptPassword("Backup Password", informative: "Encrypts the backup. No recovery if forgotten.") else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FOGNote \(Date.now.formatted(.dateTime.year().month().day())).fogbackup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BackupService.backUp(to: url, password: password)
            NSAlert.show(title: "Backup Complete", message: "Encrypted backup saved to \(url.lastPathComponent).")
        } catch {
            NSAlert.show(title: "Backup Failed", message: error.localizedDescription)
        }
    }

    private func runRestore() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let password = promptPassword("Backup Password", informative: "Password used when this backup was created. FOGNote will relaunch after restoring.") else { return }
        do {
            try BackupService.restore(from: url, password: password)
        } catch {
            NSAlert.show(title: "Restore Failed", message: error.localizedDescription)
        }
    }
}

import AppKit
