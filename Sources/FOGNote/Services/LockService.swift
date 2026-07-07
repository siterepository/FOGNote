import Foundation
import CryptoKit

/// Per-note password protection. Stores a salted SHA-256 hash on the note;
/// unlocked note IDs are kept in AppState for the session only.
enum LockService {
    static func hash(password: String, noteID: UUID) -> Data {
        let salted = Data((noteID.uuidString + password).utf8)
        return Data(SHA256.hash(data: salted))
    }

    static func setLock(on note: Note, password: String) {
        note.lockPasswordHash = hash(password: password, noteID: note.id)
        note.isLocked = true
    }

    static func verify(password: String, note: Note) -> Bool {
        guard let stored = note.lockPasswordHash else { return false }
        return hash(password: password, noteID: note.id) == stored
    }

    static func removeLock(from note: Note) {
        note.isLocked = false
        note.lockPasswordHash = nil
    }
}
