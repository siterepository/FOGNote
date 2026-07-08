import SwiftUI
import SwiftData
import AppKit

struct MenuBarContent: View {
    let container: ModelContainer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Quick Capture (⌃⌥N)") {
            QuickCapturePanel.shared.show(container: container)
        }
        Button("Today's Daily Note") {
            let note = TemplateEngine.dailyNote(context: container.mainContext)
            openMain()
            NotificationCenter.default.post(name: .fogSelectNote, object: note.persistentModelID)
        }
        Divider()
        Button("Open FOGNote") { openMain() }
        Button("Insights") {
            openWindow(id: "insights")
            NSApp.activate()
        }
        Button("Sales Library") {
            openWindow(id: "library")
            NSApp.activate()
        }
        Divider()
        Button("Quit FOGNote") { NSApp.terminate(nil) }
    }

    private func openMain() {
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue.contains("FOGNote") ?? ($0.title == "FOGNote" || $0.contentViewController != nil) }?
            .makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let fogSelectNote = Notification.Name("fogSelectNote")
}
