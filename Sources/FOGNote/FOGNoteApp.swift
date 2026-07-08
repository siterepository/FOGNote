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
            Attachment.self, NoteVersion.self, SavedSearch.self, Recording.self, Snippet.self
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

        let container = container
        HotKeyManager.shared.onHotKey = {
            QuickCapturePanel.shared.toggle(container: container)
        }
        HotKeyManager.shared.register()
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

        Window("Sales Library", id: "library") {
            LibraryView()
                .environment(appState)
        }
        .modelContainer(container)

        Window("About FOGNote", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Insights", id: "insights") {
            InsightsView()
        }
        .modelContainer(container)

        Window("Note Graph", id: "graph") {
            GraphViewWindow()
                .environment(appState)
        }
        .modelContainer(container)

        MenuBarExtra {
            MenuBarContent(container: container)
                .environment(appState)
        } label: {
            Image(systemName: "cloud.fog.fill")
        }
        .modelContainer(container)

        Settings {
            SettingsView()
        }
    }
}
