import SwiftUI
import SwiftData
import AppKit

/// The Prospect Hub: one chronological activity timeline per deal (notebook)
/// or contact (tag) — every note, call, AI summary, bookmark, and open action
/// item in one place, with a CRM-ready export.
struct ProspectHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let title: String
    let notes: [Note]

    enum Entry: Identifiable {
        case note(Note)
        case recording(Recording)

        var id: PersistentIdentifier {
            switch self {
            case .note(let note): note.persistentModelID
            case .recording(let recording): recording.persistentModelID
            }
        }

        var date: Date {
            switch self {
            case .note(let note): note.createdAt
            case .recording(let recording): recording.createdAt
            }
        }
    }

    private var entries: [Entry] {
        var result: [Entry] = notes.map { .note($0) }
        result += notes.flatMap(\.recordings).map { Entry.recording($0) }
        return result.sorted { $0.date > $1.date }
    }

    private var openActionItems: [(note: Note, line: String)] {
        notes.flatMap { note in
            note.bodyPlainText.split(separator: "\n")
                .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("☐") }
                .map { (note, $0.trimmingCharacters(in: .whitespaces)) }
        }
    }

    private var callStats: (count: Int, avgScore: Int?, lastTouch: Date?) {
        let recordings = notes.flatMap(\.recordings)
        let scores = recordings.compactMap { recording -> Int? in
            guard let range = recording.summary.range(of: #"Call score: (\d+)/100"#, options: .regularExpression),
                  let score = Int(recording.summary[range].dropFirst("Call score: ".count).dropLast(4)) else { return nil }
            return score
        }
        let lastTouch = entries.first?.date
        return (recordings.count, scores.isEmpty ? nil : scores.reduce(0, +) / scores.count, lastTouch)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: "person.crop.square.filled.and.at.rectangle")
                    .font(.title3.bold())
                Spacer()
                Button {
                    exportDealSheet()
                } label: {
                    Label("Copy Deal Sheet", systemImage: "doc.on.clipboard")
                }
                .help("CRM-ready Markdown summary to clipboard")
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()

            HStack(spacing: 20) {
                stat("Notes", "\(notes.count)")
                stat("Calls", "\(callStats.count)")
                if let avg = callStats.avgScore { stat("Avg Score", "\(avg)/100") }
                if let last = callStats.lastTouch { stat("Last Touch", last.formatted(date: .abbreviated, time: .omitted)) }
                stat("Open Items", "\(openActionItems.count)")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !openActionItems.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(openActionItems.prefix(6).enumerated()), id: \.offset) { _, item in
                            Button {
                                appState.selectedNoteID = item.note.persistentModelID
                                dismiss()
                            } label: {
                                Text(item.line).font(.caption).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Open Action Items", systemImage: "checklist")
                        .font(.caption.bold())
                        .foregroundStyle(Color.fogWarn)
                }
                .padding(.horizontal, 14)
            }

            List(entries) { entry in
                timelineRow(entry)
            }
            .listStyle(.inset)
        }
        .frame(width: 620, height: 560)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func timelineRow(_ entry: Entry) -> some View {
        switch entry {
        case .note(let note):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(Color.fogAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "Untitled" : note.title).font(.callout.bold())
                    Text(note.previewText.prefix(140)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.selectedNoteID = note.persistentModelID
                dismiss()
            }
        case .recording(let recording):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "waveform.circle.fill").foregroundStyle(Color(hex: "#E5484D"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title).font(.callout.bold())
                    if !recording.summary.isEmpty {
                        Text(recording.summary.split(separator: "\n").dropFirst().first.map(String.init) ?? "")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                        if recording.talkSecondsMe + recording.talkSecondsThem > 0 {
                            Text("Talk \(Int((recording.talkRatioMe * 100).rounded()))% you")
                        }
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func exportDealSheet() {
        var out = "# Deal Sheet — \(title)\n\n"
        let stats = callStats
        out += "- Notes: \(notes.count)  |  Calls: \(stats.count)"
        if let avg = stats.avgScore { out += "  |  Avg call score: \(avg)/100" }
        if let last = stats.lastTouch { out += "  |  Last touch: \(last.formatted(date: .abbreviated, time: .omitted))" }
        out += "\n\n## Open Action Items\n"
        out += openActionItems.map { "- [ ] \($0.line.dropFirst(2)) (\($0.note.title))" }.joined(separator: "\n")
        out += "\n\n## Call Summaries\n\n"
        for recording in notes.flatMap(\.recordings).sorted(by: { $0.createdAt > $1.createdAt }) where !recording.summary.isEmpty {
            out += recording.summary + "\n\n---\n\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
        NSAlert.show(title: "Deal Sheet Copied", message: "CRM-ready Markdown for “\(title)” is on your clipboard.")
    }
}
