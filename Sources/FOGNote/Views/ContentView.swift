import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } content: {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let id = appState.selectedNoteID,
               let note = context.registeredModel(for: id) as Note? {
                NoteDetailView(note: note)
                    .id(id)
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
    }
}
