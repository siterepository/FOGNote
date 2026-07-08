import SwiftUI
import SwiftData

/// Live recording pane, docked as a right-side inspector in the main window —
/// take notes in the editor while the call records beside them.
struct RecordingPanel: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var recorder: CallRecorder
    let note: Note
    @Binding var isPresented: Bool

    @AppStorage("autoSummarize") private var autoSummarize = true

    var body: some View {
        VStack(spacing: 12) {
            header

            switch recorder.state {
            case .idle:
                preflight
            case .recording, .paused:
                liveView
            case .processing(let stage):
                VStack(spacing: 10) {
                    ProgressView()
                    Text(stage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.fogWarn)
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Button("OK") {
                        recorder.dismissFailure()
                        isPresented = false
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            Label("Call Recording", systemImage: "waveform.circle.fill")
                .font(.headline)
                .foregroundStyle(Color(hex: "#E5484D"))
            Spacer()
            if recorder.isActive {
                Text(timeString(recorder.elapsed))
                    .font(.system(.title3, design: .monospaced).bold())
                    .contentTransition(.numericText())
            }
        }
    }

    private var preflight: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record this call into “\(note.title.isEmpty ? "New Note" : note.title)”. Keep typing notes — recording runs beside the editor.")
                .font(.callout)
            Toggle(isOn: $recorder.captureSystemAudio) {
                VStack(alignment: .leading) {
                    Text("Capture system audio")
                    Text("Records the other side of Zoom/Teams/browser calls. macOS will ask for audio-capture permission on first use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $recorder.liveTranscription) {
                VStack(alignment: .leading) {
                    Text("Live transcription")
                    Text("On-device. Mic is labeled “Me”, system audio “Them”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await recorder.start(note: note) }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: "#E5484D"))
            Button("Close") { isPresented = false }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var liveView: some View {
        VStack(spacing: 10) {
            if let target = recorder.targetNoteUUID, target != note.id {
                Label("Recording into “\(recorder.targetNoteTitle.isEmpty ? "another note" : recorder.targetNoteTitle)” — keeps going while you browse.", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(Color.fogWarn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    meter(label: "Me", level: recorder.micLevel, color: Color.fogAccent)
                    if recorder.captureSystemAudio {
                        meter(label: "Them", level: recorder.systemLevel, color: Color.fogSecondary)
                    }
                    Spacer()
                }
                let ratio = recorder.talkSecondsMe + recorder.talkSecondsThem > 0
                    ? Int((recorder.talkSecondsMe / (recorder.talkSecondsMe + recorder.talkSecondsThem) * 100).rounded())
                    : 0
                Text("Talk: \(ratio)% you")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(ratio > 60 ? AnyShapeStyle(Color.fogWarn) : AnyShapeStyle(.secondary))
                    .help("Top reps stay near 43%. Amber above 60%.")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if recorder.transcriptLines.isEmpty {
                            Text(recorder.liveTranscription ? "Listening…" : "Live transcription off")
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(recorder.transcriptLines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.speaker)
                                    .font(.caption.bold())
                                    .foregroundStyle(line.speaker == "Me" ? Color.fogAccent : Color.fogSecondary)
                                    .frame(width: 40, alignment: .trailing)
                                Text(line.text)
                                    .font(.callout)
                                    .opacity(line.isFinal ? 1 : 0.55)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: recorder.transcriptLines) {
                    if let last = recorder.transcriptLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if !recorder.bookmarks.isEmpty {
                HStack {
                    Image(systemName: "flag.fill").foregroundStyle(Color.fogWarn)
                    Text(recorder.bookmarks.map { timeString($0) }.joined(separator: "  "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Button {
                    recorder.addBookmark()
                } label: {
                    Label("Bookmark", systemImage: "flag")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("m", modifiers: .command)
                .help("Flag this moment (⌘M)")

                Button {
                    recorder.togglePause()
                } label: {
                    Label(recorder.state == .paused ? "Resume" : "Pause",
                          systemImage: recorder.state == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
            }

            Button {
                Task { await finishRecording() }
            } label: {
                Label("Stop & Save", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: "#E5484D"))
        }
    }

    private func meter(label: String, level: Float, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption.bold()).foregroundStyle(color)
            Capsule()
                .fill(.quaternary)
                .frame(width: 70, height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: CGFloat(min(1, level * 12)) * 70)
                }
                .animation(.linear(duration: 0.1), value: level)
        }
    }

    private func finishRecording() async {
        guard let recording = await recorder.finishAndSave() else {
            if case .failed = recorder.state {} else { isPresented = false }
            return
        }
        isPresented = false

        if autoSummarize && !recording.transcript.isEmpty {
            let summary = (try? await SummaryService.summarize(recording: recording)) ?? ""
            if !summary.isEmpty {
                recording.summary = summary
                try? context.save()
            }
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
