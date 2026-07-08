import Foundation
import UserNotifications
import SwiftData

/// Real macOS notifications for note reminders.
@MainActor
enum NotificationService {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable _, _ in }
    }

    static func sync(note: Note) {
        let center = UNUserNotificationCenter.current()
        let id = "fognote-reminder-\(note.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let date = note.reminderDate, !note.reminderDone, date > .now, !note.isTrashed else { return }
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = note.title.isEmpty ? "FOGNote Reminder" : note.title
        content.body = note.isLocked ? "Locked note reminder" : String(note.previewText.prefix(120))
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Re-arm everything at launch (survives reboots, edits made pre-feature).
    static func syncAll(context: ModelContext) {
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        for note in notes where note.reminderDate != nil {
            sync(note: note)
        }
    }
}
