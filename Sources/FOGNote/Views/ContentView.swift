import SwiftUI
import SwiftData

import AppKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } content: {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let noteID = appState.selectedNoteID,
               let note = context.registeredModel(for: noteID) as Note? {
                NoteDetailView(note: note)
                    .id(noteID)
            } else {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "cloud.fog",
                    description: Text("Select a note or press ⌘N to create one.")
                )
            }
        }
        .searchable(text: $appState.searchText, placement: .sidebar, prompt: "Search notes, tag:name…")
        .frame(minWidth: 940, minHeight: 560)
        .task { NotificationService.syncAll(context: context) }
        .task {
            let args = ProcessInfo.processInfo.arguments
            for id in ["insights", "library", "graph", "about"] where args.contains("--uitest-\(id)") {
                openWindow(id: id)
            }
            if args.contains("--uitest-record") {
                await Self.runRecordSmokeTest()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fogSelectNote)) { notification in
            if let id = notification.object as? PersistentIdentifier {
                appState.sidebarSelection = .allNotes
                appState.selectedNoteID = id
            }
        }
    }

    /// End-to-end recording smoke test (--uitest-record): 5 s mic-only
    /// recording through the full tap → write → mix → MP3 pipeline, result to
    /// /tmp/fognote-uitest-record.txt, then quit.
    @MainActor
    static func runRecordSmokeTest() async {
        let recorder = CallRecorder()
        recorder.captureSystemAudio = false
        recorder.liveTranscription = ProcessInfo.processInfo.arguments.contains("--uitest-record-transcribe")
        await recorder.start()
        var report = "state-after-start=\(recorder.state)"
        if recorder.state == .recording {
            try? await Task.sleep(for: .seconds(5))
            let result = await recorder.stop()
            report += " result=\(result.map { "\($0.fileName) \(String(format: "%.1f", $0.duration))s" } ?? "nil") final-state=\(recorder.state)"
        }
        try? report.write(toFile: "/tmp/fognote-uitest-record.txt", atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(1))
        NSApp.terminate(nil)
    }
}
