import SwiftUI
import SwiftData
import AVFoundation
import AppKit

/// Recordings section shown under a note: players, transcripts, AI summaries,
/// follow-up email drafts, and the join-into-one tool.
struct RecordingsSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var note: Note
    @State private var joining = false

    private var sorted: [Recording] {
        note.recordings.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recordings", systemImage: "waveform.circle")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if note.recordings.count > 1 {
                    Button {
                        Task { await joinAll() }
                    } label: {
                        if joining {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Join into One MP3", systemImage: "link.badge.plus")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(joining)
                    .help("Concatenates all recordings on this note into a single MP3")
                }
            }
            ForEach(sorted) { recording in
                RecordingCard(recording: recording)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func joinAll() async {
        joining = true
        defer { joining = false }
        let files = sorted.map(\.fileURL)
        let fileName = "Joined \(Date.now.formatted(.dateTime.year().month().day().hour().minute())).mp3"
            .replacingOccurrences(of: ":", with: ".")
        let outURL = Recording.recordingsDirectory.appending(path: fileName)
        do {
            try await AudioFileMixer.join(files: files, to: outURL)
            let joined = Recording(title: "Joined — \(sorted.count) recordings", fileName: fileName)
            joined.duration = AudioFileMixer.duration(of: outURL)
            joined.transcript = sorted.map(\.transcript).filter { !$0.isEmpty }.joined(separator: "\n---\n")
            joined.talkSecondsMe = sorted.reduce(0) { $0 + $1.talkSecondsMe }
            joined.talkSecondsThem = sorted.reduce(0) { $0 + $1.talkSecondsThem }
            joined.note = note
            context.insert(joined)
            try? context.save()
        } catch {
            NSAlert.show(title: "Join Failed", message: error.localizedDescription)
        }
    }
}

struct RecordingCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var recording: Recording
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var showTranscript = false
    @State private var showStudio = false
    @State private var busy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.fogAccent)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title).font(.callout.bold())
                    HStack(spacing: 8) {
                        Text(timeString(recording.duration))
                        if recording.talkSecondsMe + recording.talkSecondsThem > 0 {
                            Text("Talk: \(Int((recording.talkRatioMe * 100).rounded()))% you")
                        }
                        if !recording.bookmarks.isEmpty {
                            Label("\(recording.bookmarks.count)", systemImage: "flag.fill")
                        }
                        if recording.capturedSystemAudio {
                            Label("Both sides", systemImage: "person.2.wave.2")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()

                if let busy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    actions
                }
            }

            if !recording.bookmarks.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recording.bookmarks, id: \.self) { mark in
                        Button {
                            seek(to: mark)
                        } label: {
                            Label(timeString(mark), systemImage: "flag.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(Color.fogWarn)
                    }
                }
            }

            if showTranscript && !recording.transcript.isEmpty {
                ScrollView {
                    Text(recording.transcript)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }

            if !recording.summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(Color.fogSecondary)
                    Text(LocalizedStringKey(recording.summary))
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(Color.fogSecondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                player?.stop()
                isPlaying = false
                showStudio = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open in Studio — scrub, trim, clickable transcript")
            .sheet(isPresented: $showStudio) {
                RecordingStudioView(recording: recording)
            }

            Menu {
                Button(recording.summary.isEmpty ? "Generate AI Summary" : "Regenerate AI Summary") {
                    Task { await summarize() }
                }
                Button("Draft Follow-up Email") {
                    Task { await draftEmail() }
                }
                .disabled(recording.transcript.isEmpty)
            } label: {
                Image(systemName: "sparkles")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("On-device AI (Apple Intelligence)")

            Button {
                showTranscript.toggle()
            } label: {
                Image(systemName: "text.quote")
            }
            .buttonStyle(.plain)
            .foregroundStyle(showTranscript ? Color.fogAccent : .secondary)
            .help("Show transcript")
            .disabled(recording.transcript.isEmpty)

            Menu {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.fileURL])
                }
                Button("Copy Transcript") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recording.transcript, forType: .string)
                }
                .disabled(recording.transcript.isEmpty)
                Button("Copy Summary") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recording.summary, forType: .string)
                }
                .disabled(recording.summary.isEmpty)
                Divider()
                Button("Delete Recording", role: .destructive) {
                    player?.stop()
                    try? FileManager.default.removeItem(at: recording.fileURL)
                    context.delete(recording)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Playback

    private func togglePlay() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: recording.fileURL)
        }
        player?.play()
        isPlaying = player?.isPlaying ?? false
    }

    private func seek(to seconds: Double) {
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: recording.fileURL)
        }
        player?.currentTime = seconds
        player?.play()
        isPlaying = true
    }

    // MARK: - AI

    private func summarize() async {
        busy = "Summarizing…"
        defer { busy = nil }
        do {
            recording.summary = try await SummaryService.summarize(recording: recording)
            try? context.save()
        } catch {
            NSAlert.show(title: "Summary Failed", message: error.localizedDescription)
        }
    }

    private func draftEmail() async {
        busy = "Drafting…"
        defer { busy = nil }
        do {
            let email = try await SummaryService.followUpEmail(recording: recording)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(email, forType: .string)
            NSAlert.show(title: "Follow-up Email Copied", message: "The draft is on your clipboard:\n\n\(email.prefix(400))…")
        } catch {
            NSAlert.show(title: "Draft Failed", message: error.localizedDescription)
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension NSAlert {
    @MainActor
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
