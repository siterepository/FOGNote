import SwiftUI
import SwiftData
import AVFoundation
import AppKit

/// Middle-column list of every recording in the library, newest first.
/// Selecting one opens its note in the detail pane.
struct RecordingsListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var playingID: PersistentIdentifier?
    @State private var player: AVAudioPlayer?

    var body: some View {
        Group {
            if recordings.isEmpty {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "waveform.circle",
                    description: Text("Open a note and press ⌘⇧R to record a call.")
                )
            } else {
                List(recordings, id: \.persistentModelID) { recording in
                    row(recording)
                        .contentShape(Rectangle())
                        .onTapGesture { open(recording) }
                        .contextMenu {
                            Button("Open Note") { open(recording) }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([recording.fileURL])
                            }
                            Button("Delete Recording", role: .destructive) {
                                if playingID == recording.persistentModelID { player?.stop() }
                                try? FileManager.default.removeItem(at: recording.fileURL)
                                context.delete(recording)
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Recordings")
        .navigationSubtitle("\(recordings.count) recording\(recordings.count == 1 ? "" : "s")")
    }

    private func row(_ recording: Recording) -> some View {
        HStack(spacing: 10) {
            Button {
                togglePlay(recording)
            } label: {
                Image(systemName: playingID == recording.persistentModelID ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.fogAccent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(timeString(recording.duration))
                    Text(recording.createdAt.noteListLabel)
                    if !recording.summary.isEmpty {
                        Image(systemName: "sparkles").foregroundStyle(Color.fogSecondary)
                    }
                    if !recording.transcript.isEmpty {
                        Image(systemName: "text.quote")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                if let note = recording.note {
                    Label(note.title.isEmpty ? "Untitled" : note.title, systemImage: "note.text")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.fogAccent)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func open(_ recording: Recording) {
        guard let note = recording.note else { return }
        appState.sidebarSelection = .allNotes
        appState.selectedNoteID = note.persistentModelID
    }

    private func togglePlay(_ recording: Recording) {
        if playingID == recording.persistentModelID {
            player?.pause()
            playingID = nil
            return
        }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: recording.fileURL)
        player?.play()
        playingID = recording.persistentModelID
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
