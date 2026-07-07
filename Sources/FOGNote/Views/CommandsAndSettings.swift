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
            ImportCommand()
        }
        CommandGroup(replacing: .appInfo) {
            AboutCommand()
        }
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
        Button("About FOGNote") {
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "FOGNote",
                .applicationVersion: "1.0.0",
                .credits: NSAttributedString(
                    string: "Evernote × Apple Notes, merged.\nLocal-first notes for macOS.",
                    attributes: [.font: NSFont.systemFont(ofSize: 11)]
                )
            ])
        }
    }
}

struct SettingsView: View {
    @AppStorage("noteSortOrder") private var sortOrder: NoteSortOrder = .modified
    @AppStorage("trashRetentionDays") private var trashRetentionDays = 30

    var body: some View {
        Form {
            Picker("Default sort order", selection: $sortOrder) {
                ForEach(NoteSortOrder.allCases, id: \.self) { Text($0.rawValue) }
            }
            Stepper("Empty trash after \(trashRetentionDays) days", value: $trashRetentionDays, in: 1...365)
            LabeledContent("Data location") {
                Text("~/Library/Application Support/FOGNote")
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

import AppKit
