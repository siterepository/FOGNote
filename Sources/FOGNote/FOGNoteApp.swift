import SwiftUI
import SwiftData

@main
struct FOGNoteApp: App {
    let container: ModelContainer
    @State private var appState = AppState()

    init() {
        let supportURL = URL.applicationSupportDirectory.appending(path: "FOGNote", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let storeURL = supportURL.appending(path: "FOGNote.store")
        let schema = Schema([
            Note.self, Notebook.self, Stack.self, Tag.self,
            Attachment.self, NoteVersion.self, SavedSearch.self, Recording.self
        ])
        do {
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: storeURL)
            )
        } catch {
            fatalError("Failed to open FOGNote store: \(error)")
        }
        SeedData.seedIfNeeded(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(container)
        .commands {
            FOGNoteCommands(appState: appState)
        }

        Settings {
            SettingsView()
        }
    }
}
