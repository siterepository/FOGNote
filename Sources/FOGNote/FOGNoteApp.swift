import SwiftUI
import SwiftData
import AppKit

/// Finalizes an in-flight recording before the app quits, so Stop is never
/// required to keep the audio.
final class FOGAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let recorder = CallRecorder.shared
        guard recorder.isActive else { return .terminateNow }
        Task { @MainActor in
            await recorder.finishAndSave()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct FOGNoteApp: App {
    let container: ModelContainer
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(FOGAppDelegate.self) private var appDelegate

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

        CallRecorder.shared.modelContainer = container
        Task {
            await CallRecorder.recoverOrphanedSessions(container: container)
        }
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
