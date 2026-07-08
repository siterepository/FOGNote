import SwiftUI
import SwiftData
import AppKit

/// Sales Library window: reusable snippets + the auto-aggregated objection
/// library mined from every AI call summary.
struct LibraryView: View {
    var body: some View {
        TabView {
            SnippetsTab()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            ObjectionsTab()
                .tabItem { Label("Objection Library", systemImage: "shield.lefthalf.filled") }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

struct SnippetsTab: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Snippet.name) private var snippets: [Snippet]
    @State private var selection: Snippet?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(snippets, id: \.persistentModelID, selection: Binding(
                    get: { selection.map(\.persistentModelID) },
                    set: { id in selection = snippets.first { $0.persistentModelID == id } }
                )) { snippet in
                    VStack(alignment: .leading) {
                        Text(snippet.name).font(.callout.bold())
                        Text(snippet.category).font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(snippet.persistentModelID)
                }
                Divider()
                HStack {
                    Button {
                        let snippet = Snippet(name: "New Snippet", content: "")
                        context.insert(snippet)
                        selection = snippet
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let selection {
                            context.delete(selection)
                            self.selection = nil
                        }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 180, maxWidth: 240)

            if let snippet = selection {
                SnippetEditor(snippet: snippet)
            } else {
                ContentUnavailableView(
                    "Snippets",
                    systemImage: "text.badge.plus",
                    description: Text("Reusable blocks — pricing rebuttals, follow-up paragraphs, meeting agendas. Insert from the editor toolbar. Supports {{date}}, {{time}}, {{clipboard}}.")
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
    }
}

private struct SnippetEditor: View {
    @Bindable var snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $snippet.name)
                .font(.title3.bold())
                .textFieldStyle(.plain)
            TextField("Category", text: $snippet.category)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            TextEditor(text: $snippet.content)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
    }
}

/// Mines "**Objections & Concerns**" bullets out of every recording's AI
/// summary — one deduplicated list of what prospects push back on.
struct ObjectionsTab: View {
    @Environment(\.modelContext) private var context
    @Query private var recordings: [Recording]

    struct Objection: Identifiable {
        let id = UUID()
        let text: String
        let noteTitle: String
        let date: Date
    }

    private var objections: [Objection] {
        var seen = Set<String>()
        var result: [Objection] = []
        for recording in recordings.sorted(by: { $0.createdAt > $1.createdAt }) {
            for line in Self.objectionLines(in: recording.summary) {
                let key = line.lowercased().prefix(60)
                if seen.insert(String(key)).inserted {
                    result.append(Objection(
                        text: line,
                        noteTitle: recording.note?.title ?? recording.title,
                        date: recording.createdAt
                    ))
                }
            }
        }
        return result
    }

    static func objectionLines(in summary: String) -> [String] {
        guard let range = summary.range(of: "**Objections & Concerns**") else { return [] }
        var lines: [String] = []
        for raw in summary[range.upperBound...].split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") {
                lines.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("**") {
                break
            }
        }
        return lines
    }

    var body: some View {
        Group {
            if objections.isEmpty {
                ContentUnavailableView(
                    "No Objections Yet",
                    systemImage: "shield.lefthalf.filled",
                    description: Text("Record calls with AI summaries and every objection lands here automatically — your personal battle-card library.")
                )
            } else {
                List(objections) { objection in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(objection.text)
                        HStack {
                            Text(objection.noteTitle).font(.caption).foregroundStyle(Color.fogAccent)
                            Text(objection.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("Save Response as Snippet") {
                                let snippet = Snippet(
                                    name: String(objection.text.prefix(40)),
                                    content: "Objection: \(objection.text)\n\nResponse: ",
                                    category: "Objections"
                                )
                                context.insert(snippet)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(8)
    }
}
