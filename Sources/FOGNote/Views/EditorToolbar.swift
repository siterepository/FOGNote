import SwiftUI
import SwiftData

/// Formatting toolbar for the rich-text editor.
struct EditorToolbar: View {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var onChecklist: () -> Void
    @Query(sort: \Snippet.name) private var snippets: [Snippet]
    @Environment(\.openWindow) private var openWindow

    private let sizes: [CGFloat] = [11, 12, 14, 16, 18, 22, 28]
    private let colors: [(String, Color)] = [
        ("Default", .primary),
        ("Fog Blue", Color.fogAccent),
        ("Purple", Color.fogSecondary),
        ("Amber", Color.fogWarn),
        ("Red", Color.fogLock),
        ("Green", Color(hex: "#4C9A6A"))
    ]

    var body: some View {
        HStack(spacing: 4) {
            group {
                formatButton("bold", help: "Bold (⌘B)") { toggleBold() }
                    .keyboardShortcut("b", modifiers: .command)
                formatButton("italic", help: "Italic (⌘I)") { toggleItalic() }
                    .keyboardShortcut("i", modifiers: .command)
                formatButton("underline", help: "Underline (⌘U)") { toggleUnderline() }
                    .keyboardShortcut("u", modifiers: .command)
                formatButton("strikethrough", help: "Strikethrough") { toggleStrikethrough() }
            }

            Divider().frame(height: 16)

            Menu {
                ForEach(sizes, id: \.self) { size in
                    Button("\(Int(size)) pt") { setFontSize(size) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)
            .help("Text size")

            Menu {
                ForEach(colors, id: \.0) { name, color in
                    Button {
                        setColor(name == "Default" ? nil : color)
                    } label: {
                        Label(name, systemImage: "circle.fill")
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)
            .help("Text color")

            formatButton("highlighter", help: "Highlight") { toggleHighlight() }

            Divider().frame(height: 16)

            formatButton("checklist", help: "Checklist (⌘⇧L)") { onChecklist() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            formatButton("list.bullet", help: "Bulleted line") { prefixLine("• ") }

            Divider().frame(height: 16)

            Menu {
                if snippets.isEmpty {
                    Button("No snippets yet — open Sales Library") { openWindow(id: "library") }
                } else {
                    ForEach(snippets) { snippet in
                        Button(snippet.name) { insertSnippet(snippet) }
                    }
                    Divider()
                    Button("Manage Snippets…") { openWindow(id: "library") }
                }
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)
            .help("Insert snippet")

            Spacer()
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func group(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 2) { content() }
    }

    private func formatButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 20)
        }
        .help(help)
    }

    // MARK: - Attribute transforms

    private func toggleBold() {
        text.transformAttributes(in: &selection) { container in
            let intent = container.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) {
                container.inlinePresentationIntent = intent.subtracting(.stronglyEmphasized)
            } else {
                container.inlinePresentationIntent = intent.union(.stronglyEmphasized)
            }
        }
    }

    private func toggleItalic() {
        text.transformAttributes(in: &selection) { container in
            let intent = container.inlinePresentationIntent ?? []
            if intent.contains(.emphasized) {
                container.inlinePresentationIntent = intent.subtracting(.emphasized)
            } else {
                container.inlinePresentationIntent = intent.union(.emphasized)
            }
        }
    }

    private func toggleUnderline() {
        text.transformAttributes(in: &selection) { container in
            container.underlineStyle = container.underlineStyle == nil ? .single : nil
        }
    }

    private func toggleStrikethrough() {
        text.transformAttributes(in: &selection) { container in
            container.strikethroughStyle = container.strikethroughStyle == nil ? .single : nil
        }
    }

    private func setFontSize(_ size: CGFloat) {
        text.transformAttributes(in: &selection) { container in
            container.font = .system(size: size)
        }
    }

    private func setColor(_ color: Color?) {
        text.transformAttributes(in: &selection) { container in
            container.foregroundColor = color
        }
    }

    private func toggleHighlight() {
        text.transformAttributes(in: &selection) { container in
            if container.backgroundColor == nil {
                container.backgroundColor = Color.fogWarn.opacity(0.35)
            } else {
                container.backgroundColor = nil
            }
        }
    }

    private func insertSnippet(_ snippet: Snippet) {
        let content = TemplateEngine.expand(snippet.content)
        let indices = selection.indices(in: text)
        let insertAt: AttributedString.Index
        switch indices {
        case .insertionPoint(let index):
            insertAt = index
        case .ranges(let rangeSet):
            insertAt = rangeSet.ranges.last?.upperBound ?? text.endIndex
        }
        text.characters.insert(contentsOf: content, at: insertAt)
        selection = AttributedTextSelection()
    }

    private func prefixLine(_ prefix: String) {
        let indices = selection.indices(in: text)
        let offset: Int
        switch indices {
        case .insertionPoint(let index):
            offset = text.characters.distance(from: text.startIndex, to: index)
        case .ranges(let rangeSet):
            guard let first = rangeSet.ranges.first else { return }
            offset = text.characters.distance(from: text.startIndex, to: first.lowerBound)
        }
        let plain = String(text.characters)
        let chars = Array(plain)
        var lineStart = 0
        for i in stride(from: min(offset, chars.count) - 1, through: 0, by: -1) {
            if chars[i] == "\n" { lineStart = i + 1; break }
        }
        let idx = text.characters.index(text.startIndex, offsetBy: lineStart)
        text.characters.insert(contentsOf: prefix, at: idx)
        selection = AttributedTextSelection()
    }
}
