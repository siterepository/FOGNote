import Foundation
import EventKit

/// Read-only calendar access for meeting-linked notes (Granola-style).
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    struct Meeting: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let attendees: [String]
        let location: String?
    }

    private let store = EKEventStore()
    private(set) var todaysMeetings: [Meeting] = []
    private(set) var accessDenied = false

    func refresh() async {
        let granted: Bool
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            granted = true
        } else {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        }
        guard granted else {
            accessDenied = true
            todaysMeetings = []
            return
        }
        accessDenied = false
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        todaysMeetings = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                Meeting(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Meeting",
                    start: event.startDate,
                    end: event.endDate,
                    attendees: (event.attendees ?? []).compactMap { $0.name }.filter { !$0.isEmpty },
                    location: event.location
                )
            }
    }

    /// Pre-filled prep note for a meeting, from the user's Meeting template
    /// when one exists.
    func prepNoteBody(for meeting: Meeting) -> String {
        var header = "\(meeting.start.formatted(date: .abbreviated, time: .shortened)) – \(meeting.end.formatted(date: .omitted, time: .shortened))"
        if !meeting.attendees.isEmpty {
            header += "\nAttendees: \(meeting.attendees.joined(separator: ", "))"
        }
        if let location = meeting.location, !location.isEmpty {
            header += "\nWhere: \(location)"
        }
        return header + """


        Goals
        ☐\u{20}

        Agenda
        ☐\u{20}

        Notes

        Next Steps
        ☐\u{20}
        """
    }
}
