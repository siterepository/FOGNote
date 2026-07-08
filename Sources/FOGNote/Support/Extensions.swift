import SwiftUI
import AppKit

// MARK: - Brand palette (fog)

extension Color {
    static let fogAccent = Color(hex: "#6B9FD4")
    static let fogSecondary = Color(hex: "#8B7FB3")
    static let fogWarn = Color(hex: "#F59E0B")
    static let fogLock = Color(hex: "#FF6B6B")

    init(hex: String) {
        var value = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        let scanner = Scanner(string: value)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - AttributedString <-> RTF

extension AttributedString {
    /// Decode from RTF data stored on a Note.
    init(rtfData: Data) {
        if let ns = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            self = AttributedString(ns)
        } else {
            self = AttributedString()
        }
    }

    func rtfData() -> Data {
        let ns = NSAttributedString(self)
        return (try? ns.data(
            from: NSRange(location: 0, length: ns.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    var plainText: String {
        String(characters)
    }
}

/// Opening an inspector on a full-width window can push its right edge off
/// screen. This pulls the window back inside the visible frame.
@MainActor
enum WindowFitter {
    static func clampMainWindowToScreen(delay: TimeInterval = 0.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.mainWindow ?? NSApp.keyWindow,
                  let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            var frame = window.frame
            guard !visible.contains(frame) else { return }
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

extension Date {
    var noteListLabel: String {
        if Calendar.current.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        return formatted(date: .abbreviated, time: .omitted)
    }
}
