import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case allNotes
    case pinned
    case tasks
    case templates
    case recordings
    case trash
    case notebook(PersistentIdentifier)
    case stack(PersistentIdentifier)
    case tag(PersistentIdentifier)
    case savedSearch(PersistentIdentifier)
}

@MainActor
@Observable
final class AppState {
    var sidebarSelection: SidebarItem? = .allNotes
    var selectedNoteID: PersistentIdentifier?
    var searchText: String = ""
    /// Notes unlocked for this app session.
    var unlockedNoteIDs: Set<PersistentIdentifier> = []
    var requestNewNote: Bool = false

    func isUnlocked(_ note: Note) -> Bool {
        !note.isLocked || unlockedNoteIDs.contains(note.persistentModelID)
    }
}
