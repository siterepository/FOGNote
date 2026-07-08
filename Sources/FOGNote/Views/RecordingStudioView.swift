import SwiftUI
import SwiftData
import AVFoundation
import AppKit

/// Recording Studio: right-side in-window pane — waveform player with
/// scrubbing, skip, speed, in/out trim, and a timed transcript where clicking
/// any line jumps the playhead there.
struct RecordingStudioView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var recording: Recording

    private func close() {
        appState.studioRecording = nil
    }

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var rate: Float = 1.0
    @State private var waveform: [Float] = []
    /// Parsed once at open — parsing per render made playback ticks laggy.
    @State private var segments: [TranscriptSegment] = []
    @State private var hasExactTimestamps = true
    @State private var selectionIn: Double?
    @State private var selectionOut: Double?
    @State private var busy: String?

    private var duration: Double { max(recording.duration, 0.1) }

    /// Timed segments; older recordings without timestamps get proportional
    /// estimates so click-to-seek still works approximately.
    private func buildSegments() -> [TranscriptSegment] {
        let stored = recording.segments
        if !stored.isEmpty { return stored }
        let lines = recording.transcript.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        return lines.enumerated().map { index, line in
            let speaker = line.hasPrefix("Them:") ? "Them" : "Me"
            let text = line.replacingOccurrences(of: "^(Me|Them): ?", with: "", options: .regularExpression)
            return TranscriptSegment(speaker: speaker, text: text, start: duration * Double(index) / Double(lines.count))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 10) {
                waveformView
                transport
                trimBar
            }
            .padding(12)
            Divider()
            transcriptPane
        }
        .padding(.trailing, 8)
        .onAppear(perform: setUp)
        .onDisappear(perform: tearDown)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.fogAccent)
            VStack(alignment: .leading, spacing: 1) {
                TextField("Title", text: $recording.title)
                    .textFieldStyle(.plain)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text(timeString(duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = recording.note {
                    Button {
                        appState.sidebarSelection = .allNotes
                        appState.selectedNoteID = note.persistentModelID
                    } label: {
                        Label(note.title.isEmpty ? "Untitled" : note.title, systemImage: "note.text")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
                if let busy {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(busy).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Studio")
        }
        .padding(12)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { canvasContext, canvasSize in
                let count = max(waveform.count, 1)
                let barWidth = canvasSize.width / CGFloat(count)
                // Selection shading.
                if let inPoint = selectionIn {
                    let outPoint = selectionOut ?? duration
                    let x1 = CGFloat(inPoint / duration) * canvasSize.width
                    let x2 = CGFloat(outPoint / duration) * canvasSize.width
                    canvasContext.fill(
                        Path(CGRect(x: x1, y: 0, width: max(1, x2 - x1), height: canvasSize.height)),
                        with: .color(Color.fogWarn.opacity(0.18))
                    )
                }
                let progressX = CGFloat(currentTime / duration) * canvasSize.width
                for (index, amp) in waveform.enumerated() {
                    let x = CGFloat(index) * barWidth
                    let height = max(2, CGFloat(amp) * canvasSize.height * 0.9)
                    let y = (canvasSize.height - height) / 2
                    let played = x <= progressX
                    canvasContext.fill(
                        Path(roundedRect: CGRect(x: x, y: y, width: max(1, barWidth - 1), height: height), cornerRadius: 1),
                        with: .color(played ? Color.fogAccent : Color.fogAccent.opacity(0.28))
                    )
                }
                // Bookmarks.
                for mark in recording.bookmarks {
                    let x = CGFloat(mark / duration) * canvasSize.width
                    canvasContext.fill(
                        Path(CGRect(x: x, y: 0, width: 2, height: canvasSize.height)),
                        with: .color(Color.fogWarn)
                    )
                }
                // Playhead.
                canvasContext.fill(
                    Path(CGRect(x: progressX, y: 0, width: 2, height: canvasSize.height)),
                    with: .color(.white)
                )
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seek(to: duration * min(max(0, value.location.x / size.width), 1))
                    }
            )
            .overlay {
                if waveform.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(height: 96)
        .help("Click or drag to scrub")
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 10) {
            Text(timeString(currentTime))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 52, alignment: .trailing)

            Spacer(minLength: 0)
            Button { seek(to: currentTime - 15) } label: {
                Image(systemName: "gobackward.15").font(.body)
            }
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.fogAccent)
            }
            .keyboardShortcut(.space, modifiers: [])
            Button { seek(to: currentTime + 15) } label: {
                Image(systemName: "goforward.15").font(.body)
            }
            Spacer(minLength: 0)

            Text(timeString(duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Picker("Speed", selection: $rate) {
                ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Text(speed == 1.0 ? "1×" : String(format: "%g×", speed)).tag(speed)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .onChange(of: rate) { if isPlaying { player?.rate = rate } }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trim

    private var trimBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    selectionIn = currentTime
                    if let out = selectionOut, out <= currentTime { selectionOut = nil }
                } label: {
                    Label(selectionIn.map { "In \(timeString($0))" } ?? "Set In", systemImage: "chevron.left.to.line")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    selectionOut = currentTime
                    if let inPoint = selectionIn, inPoint >= currentTime { selectionIn = 0 }
                } label: {
                    Label(selectionOut.map { "Out \(timeString($0))" } ?? "Set Out", systemImage: "chevron.right.to.line")
                        .frame(maxWidth: .infinity)
                }
                if selectionIn != nil || selectionOut != nil {
                    Button("Clear") { selectionIn = nil; selectionOut = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button {
                    Task { await saveSelection(asNew: true) }
                } label: {
                    Label("Save as New Clip", systemImage: "square.and.arrow.down.on.square")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!hasSelection || busy != nil)
                Button(role: .destructive) {
                    confirmTrim()
                } label: {
                    Label("Trim", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!hasSelection || busy != nil)
                .help("Replaces this recording's audio with the selected range")
            }
        }
        .controlSize(.small)
    }

    private var hasSelection: Bool {
        let inPoint = selectionIn ?? 0
        let outPoint = selectionOut ?? duration
        return outPoint - inPoint > 0.5 && (selectionIn != nil || selectionOut != nil)
    }

    // MARK: - Transcript

    private var transcriptPane: some View {
        Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "text.quote",
                    description: Text("Enable live transcription when recording to get a clickable transcript.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if !hasExactTimestamps {
                                Text("Older recording — timestamps are estimated.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.bottom, 4)
                            }
                            ForEach(segments) { segment in
                                transcriptRow(segment)
                                    .id(segment.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: currentSegmentID) { _, id in
                        if let id, isPlaying {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var currentSegmentID: UUID? {
        segments.last(where: { $0.start <= currentTime })?.id
    }

    private func transcriptRow(_ segment: TranscriptSegment) -> some View {
        let isCurrent = segment.id == currentSegmentID
        return Button {
            seek(to: segment.start)
            if !isPlaying { togglePlay() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(timeString(segment.start))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.fogAccent)
                    .frame(width: 52, alignment: .trailing)
                Text(segment.speaker)
                    .font(.caption.bold())
                    .foregroundStyle(segment.speaker == "Me" ? Color.fogAccent : Color.fogSecondary)
                    .frame(width: 38, alignment: .leading)
                Text(segment.text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isCurrent ? Color.fogAccent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Jump to \(timeString(segment.start))")
    }

    // MARK: - Player plumbing (AVPlayer: instant start, fast seeks,
    // pitch-corrected speed — no full-file scan like AVAudioPlayer)

    private func setUp() {
        segments = buildSegments()
        hasExactTimestamps = !recording.segments.isEmpty

        let item = AVPlayerItem(url: recording.fileURL)
        item.audioTimePitchAlgorithm = .spectral
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        player = avPlayer
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            Task { @MainActor in
                currentTime = time.seconds
                if isPlaying && avPlayer.rate == 0 { isPlaying = false }
            }
        }

        // Waveform: cached on the model after first computation.
        let cached = recording.waveform
        if !cached.isEmpty {
            waveform = cached
        } else {
            Task.detached(priority: .userInitiated) { [url = recording.fileURL] in
                let wave = AudioFileMixer.waveform(of: url)
                await MainActor.run {
                    waveform = wave
                    recording.waveform = wave
                    try? context.save()
                }
            }
        }
    }

    private func tearDown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
    }

    private func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.rate = rate
        }
        isPlaying.toggle()
    }

    private func seek(to time: Double) {
        let clamped = min(max(0, time), duration - 0.05)
        currentTime = clamped
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .init(seconds: 0.2, preferredTimescale: 600),
            toleranceAfter: .init(seconds: 0.2, preferredTimescale: 600)
        )
    }

    // MARK: - Trim actions

    private func confirmTrim() {
        let alert = NSAlert()
        alert.messageText = "Trim Recording?"
        alert.informativeText = "The audio outside \(timeString(selectionIn ?? 0))–\(timeString(selectionOut ?? duration)) will be removed from this recording. This can't be undone."
        alert.addButton(withTitle: "Trim")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await saveSelection(asNew: false) }
        }
    }

    private func saveSelection(asNew: Bool) async {
        let inPoint = selectionIn ?? 0
        let outPoint = selectionOut ?? duration
        guard outPoint > inPoint else { return }
        busy = asNew ? "Exporting…" : "Trimming…"
        defer { busy = nil }
        player?.pause()
        isPlaying = false

        let fileName = "\(asNew ? "Clip" : "Trim") \(Date.now.formatted(.dateTime.month().day().hour().minute().second())).mp3"
            .replacingOccurrences(of: ":", with: ".")
        let outURL = Recording.recordingsDirectory.appending(path: fileName)
        do {
            try await AudioFileMixer.excerpt(source: recording.fileURL, from: inPoint, to: outPoint, toMP3: outURL)
            let shifted = segments
                .filter { $0.start >= inPoint && $0.start <= outPoint }
                .map { TranscriptSegment(speaker: $0.speaker, text: $0.text, start: $0.start - inPoint) }
            if asNew {
                let clip = Recording(title: recording.title + " (clip)", fileName: fileName)
                clip.duration = AudioFileMixer.duration(of: outURL)
                clip.segments = shifted
                clip.transcript = shifted.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
                clip.note = recording.note
                context.insert(clip)
                try? context.save()
            } else {
                try? FileManager.default.removeItem(at: recording.fileURL)
                recording.fileName = fileName
                recording.duration = AudioFileMixer.duration(of: outURL)
                recording.segments = shifted
                recording.transcript = shifted.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
                recording.bookmarks = recording.bookmarks
                    .filter { $0 >= inPoint && $0 <= outPoint }
                    .map { $0 - inPoint }
                recording.waveform = []
                try? context.save()
                selectionIn = nil
                selectionOut = nil
                waveform = []
                tearDown()
                setUp()
                seek(to: 0)
            }
        } catch {
            NSAlert.show(title: asNew ? "Export Failed" : "Trim Failed", message: error.localizedDescription)
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
