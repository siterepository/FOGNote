import SwiftUI
import AppKit
import Carbon.HIToolbox
import SwiftData

/// Global hotkey (⌃⌥N) via Carbon RegisterEventHotKey — works system-wide,
/// no Accessibility permission required. Opens the floating quick-capture
/// panel from any app.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    var onHotKey: (() -> Void)?

    func register() {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in
                HotKeyManager.shared.onHotKey?()
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x464F_474E) /* FOGN */, id: 1)
        // ⌃⌥N
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

/// Floating capture panel: type, hit ⏎, note lands in FOGNote. Esc closes.
@MainActor
final class QuickCapturePanel {
    static let shared = QuickCapturePanel()
    private var panel: NSPanel?

    func toggle(container: ModelContainer) {
        if let panel, panel.isVisible {
            panel.close()
            self.panel = nil
            return
        }
        show(container: container)
    }

    func show(container: ModelContainer) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 170),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: QuickCaptureView(
            container: container,
            close: { [weak panel] in panel?.close() }
        ))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.panel = panel
    }
}

struct QuickCaptureView: View {
    let container: ModelContainer
    let close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.fog.fill").foregroundStyle(Color.fogAccent)
                Text("Quick Capture").font(.headline)
                Spacer()
                Text("⏎ save · esc close").font(.caption2).foregroundStyle(.tertiary)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .focused($focused)
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .frame(height: 84)
            HStack {
                Spacer()
                Button("Save to FOGNote") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.fogAccent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .onAppear { focused = true }
        .onExitCommand { close() }
        .onSubmit { save() }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { close(); return }
        let context = container.mainContext
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? "Quick Note"
        let note = Note(title: String(firstLine.prefix(60)))
        var attr = AttributedString(trimmed)
        attr.font = .system(size: 14)
        note.bodyData = attr.rtfData()
        note.bodyPlainText = trimmed
        context.insert(note)
        try? context.save()
        close()
    }
}
