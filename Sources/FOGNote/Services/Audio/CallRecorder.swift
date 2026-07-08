import Foundation
import AVFoundation
import SwiftUI
import SwiftData

/// Thread-safe track writer used from audio callbacks.
final class TrackWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let lock = NSLock()

    init(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        try? file.write(from: buffer)
    }
}

@MainActor
@Observable
final class CallRecorder {
    /// App-wide recorder: recording is sticky — it survives switching notes,
    /// sidebar tabs, and window focus, and only stops on explicit Stop,
    /// app quit (finalized first), or crash (recovered at next launch).
    static let shared = CallRecorder()

    /// Injected once at app startup; used to save recordings to the store.
    var modelContainer: ModelContainer?

    enum State: Equatable {
        case idle
        case recording
        case paused
        case processing(String)
        case failed(String)
    }

    /// Where in-flight session audio lives (survives crashes for recovery).
    static var inProgressDirectory: URL {
        let dir = URL.applicationSupportDirectory
            .appending(path: "FOGNote", directoryHint: .isDirectory)
            .appending(path: "InProgress", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct TranscriptLine: Identifiable, Equatable {
        let id = UUID()
        var speaker: String
        var text: String
        var isFinal: Bool
        var start: Double = 0
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var micLevel: Float = 0
    private(set) var systemLevel: Float = 0
    private(set) var transcriptLines: [TranscriptLine] = []
    private(set) var bookmarks: [Double] = []
    var captureSystemAudio = true
    var liveTranscription = true

    // Talk-time metrics.
    private(set) var talkSecondsMe: Double = 0
    private(set) var talkSecondsThem: Double = 0
    private(set) var longestMonologueMe: Double = 0
    private var currentMonologueMe: Double = 0

    private let engine = AVAudioEngine()
    private let systemTap = SystemAudioTap()
    private var micWriter: TrackWriter?
    private var systemWriter: TrackWriter?
    private var micTranscriber: LiveTranscriber?
    private var systemTranscriber: LiveTranscriber?
    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var micTempURL: URL?
    private var systemTempURL: URL?
    private var sessionDir: URL?
    private var isPausedFlag = ThreadSafeFlag()

    /// The note this recording will be saved into (set at start, so switching
    /// notes mid-call never re-targets the save).
    private(set) var targetNoteUUID: UUID?
    private(set) var targetNoteTitle: String = ""

    var isActive: Bool {
        state == .recording || state == .paused
    }

    // MARK: - Start

    func start(note: Note? = nil) async {
        guard state == .idle else { return }
        targetNoteUUID = note?.id
        targetNoteTitle = note?.title ?? ""
        transcriptLines = []
        bookmarks = []
        talkSecondsMe = 0
        talkSecondsThem = 0
        longestMonologueMe = 0
        currentMonologueMe = 0
        pausedAccumulated = 0
        elapsed = 0

        // Audio streams straight into a persistent session folder so a crash
        // or force-quit never loses it — recovery runs at next launch.
        let session = Self.inProgressDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        sessionDir = session
        let micURL = session.appending(path: "mic.caf")
        let sysURL = session.appending(path: "sys.caf")
        micTempURL = micURL
        systemTempURL = captureSystemAudio ? sysURL : nil
        writeSessionMeta()

        do {
            // Microphone: tap all channels at the device's native format.
            let input = engine.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0 else {
                throw NSError(domain: "FOGNote", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "No microphone input available. Check System Settings → Privacy → Microphone."
                ])
            }
            let micWriter = try TrackWriter(url: micURL, format: micFormat)
            self.micWriter = micWriter

            if liveTranscription {
                let authorized = await LiveTranscriber.requestAuthorization()
                if authorized {
                    let mic = LiveTranscriber(speaker: "Me")
                    mic.onSegment = { [weak self] speaker, text, isFinal, start in
                        self?.appendSegment(speaker: speaker, text: text, isFinal: isFinal, start: start)
                    }
                    try? await mic.start(sourceFormat: micFormat)
                    micTranscriber = mic
                }
            }

            // The tap runs on AVAudioEngine's realtime messenger queue. The
            // block MUST be built nonisolated + @Sendable — a MainActor-
            // inferred closure SIGTRAPs the first time audio arrives.
            let onMicActivity: @Sendable (Float, Double) -> Void = { [weak self] level, duration in
                Task { @MainActor in
                    self?.registerMicActivity(level: level, duration: duration)
                }
            }
            input.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: micFormat,
                block: Self.micTapBlock(
                    paused: isPausedFlag,
                    writer: micWriter,
                    transcriber: micTranscriber,
                    sampleRate: micFormat.sampleRate,
                    onActivity: onMicActivity
                )
            )
            engine.prepare()
            try engine.start()

            // System audio via CoreAudio process tap.
            if captureSystemAudio {
                try systemTap.start()
                if let tapFormat = systemTap.format {
                    let systemWriter = try TrackWriter(url: sysURL, format: tapFormat)
                    self.systemWriter = systemWriter

                    if liveTranscription {
                        let sys = LiveTranscriber(speaker: "Them")
                        sys.onSegment = { [weak self] speaker, text, isFinal, start in
                            self?.appendSegment(speaker: speaker, text: text, isFinal: isFinal, start: start)
                        }
                        try? await sys.start(sourceFormat: tapFormat)
                        systemTranscriber = sys
                    }
                    let onSystemActivity: @Sendable (Float, Double) -> Void = { [weak self] level, duration in
                        Task { @MainActor in
                            self?.registerSystemActivity(level: level, duration: duration)
                        }
                    }
                    systemTap.onBuffer = Self.systemTapBlock(
                        paused: isPausedFlag,
                        writer: systemWriter,
                        transcriber: systemTranscriber,
                        onActivity: onSystemActivity
                    )
                }
            }

            startedAt = .now
            state = .recording
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let startedAt = self.startedAt, self.state == .recording else { return }
                    self.elapsed = Date.now.timeIntervalSince(startedAt) - self.pausedAccumulated
                }
            }
            self.timer = timer
        } catch {
            teardownCapture()
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Audio-thread callbacks (nonisolated by construction)

    nonisolated private static func micTapBlock(
        paused: ThreadSafeFlag,
        writer: TrackWriter,
        transcriber: LiveTranscriber?,
        sampleRate: Double,
        onActivity: @escaping @Sendable (Float, Double) -> Void
    ) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { @Sendable buffer, _ in
            guard !paused.value else { return }
            writer.write(buffer)
            let level = buffer.rmsLevel()
            if let copy = buffer.deepCopy() {
                transcriber?.feed(copy)
            }
            onActivity(level, Double(buffer.frameLength) / sampleRate)
        }
    }

    nonisolated private static func systemTapBlock(
        paused: ThreadSafeFlag,
        writer: TrackWriter,
        transcriber: LiveTranscriber?,
        onActivity: @escaping @Sendable (Float, Double) -> Void
    ) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { @Sendable buffer in
            guard !paused.value else { return }
            writer.write(buffer)
            let level = buffer.rmsLevel()
            let duration = Double(buffer.frameLength) / buffer.format.sampleRate
            if let copy = buffer.deepCopy() {
                transcriber?.feed(copy)
            }
            onActivity(level, duration)
        }
    }

    // MARK: - Controls

    private var pauseBeganAt: Date?

    func togglePause() {
        switch state {
        case .recording:
            isPausedFlag.value = true
            pauseBeganAt = .now
            state = .paused
        case .paused:
            if let began = pauseBeganAt {
                pausedAccumulated += Date.now.timeIntervalSince(began)
            }
            isPausedFlag.value = false
            state = .recording
        default:
            break
        }
    }

    func addBookmark() {
        guard isActive else { return }
        bookmarks.append(elapsed)
    }

    /// Stops capture, mixes tracks, encodes MP3. Returns (mp3FileName, duration).
    func stop() async -> (fileName: String, duration: TimeInterval)? {
        guard isActive else { return nil }
        state = .processing("Finishing transcription…")
        teardownCapture()

        await micTranscriber?.finish()
        await systemTranscriber?.finish()
        micTranscriber = nil
        systemTranscriber = nil

        guard let micTempURL else {
            state = .idle
            return nil
        }

        do {
            state = .processing("Mixing audio…")
            let wavURL = FileManager.default.temporaryDirectory
                .appending(path: "fognote-mix-\(UUID().uuidString).wav")
            let mixTask = Task.detached(priority: .userInitiated) { [systemTempURL] in
                try AudioFileMixer.mix(trackA: micTempURL, trackB: systemTempURL, to: wavURL)
            }
            try await mixTask.value

            state = .processing("Encoding MP3…")
            let fileName = "Call \(Date.now.formatted(.dateTime.year().month().day().hour().minute())).mp3"
                .replacingOccurrences(of: ":", with: ".")
            let mp3URL = Recording.recordingsDirectory.appending(path: fileName)
            try await AudioFileMixer.encodeMP3(source: wavURL, destination: mp3URL)
            let duration = AudioFileMixer.duration(of: mp3URL)

            try? FileManager.default.removeItem(at: wavURL)
            if let sessionDir { try? FileManager.default.removeItem(at: sessionDir) }
            sessionDir = nil

            state = .idle
            return (fileName, duration)
        } catch {
            // Session folder is left on disk — recovery will save it later.
            state = .failed("Audio processing failed: \(error.localizedDescription). The raw audio is safe and will be recovered on next launch.")
            return nil
        }
    }

    /// Stop + persist as a Recording model on the target note (or a new note
    /// when there is none). The one true save path — used by the panel, app
    /// termination, and anything else that ends a call.
    @discardableResult
    func finishAndSave() async -> Recording? {
        let segments = timedSegments
        let transcript = transcriptText
        let talkMe = talkSecondsMe
        let talkThem = talkSecondsThem
        let marks = bookmarks
        let capturedSystem = captureSystemAudio
        let noteUUID = targetNoteUUID

        guard let result = await stop(), let container = modelContainer else { return nil }
        let context = container.mainContext

        let note: Note
        if let noteUUID,
           let existing = try? context.fetch(FetchDescriptor<Note>()).first(where: { $0.id == noteUUID }) {
            note = existing
        } else {
            note = Note(title: "Call — \(Date.now.formatted(date: .abbreviated, time: .shortened))")
            context.insert(note)
        }

        let recording = Recording(
            title: "Call — \(Date.now.formatted(date: .abbreviated, time: .shortened))",
            fileName: result.fileName
        )
        recording.duration = result.duration
        recording.transcript = transcript
        recording.segments = segments
        recording.talkSecondsMe = talkMe
        recording.talkSecondsThem = talkThem
        recording.bookmarks = marks
        recording.capturedSystemAudio = capturedSystem
        recording.note = note
        context.insert(recording)
        note.modifiedAt = .now
        try? context.save()
        return recording
    }

    // MARK: - Session persistence & crash recovery

    private struct SessionMeta: Codable {
        var noteUUID: UUID?
        var startedAt: Date
        var captureSystemAudio: Bool
    }

    private func writeSessionMeta() {
        guard let sessionDir else { return }
        let meta = SessionMeta(noteUUID: targetNoteUUID, startedAt: .now, captureSystemAudio: captureSystemAudio)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: sessionDir.appending(path: "meta.json"))
        }
    }

    func flushTranscript() {
        guard let sessionDir else { return }
        try? transcriptText.write(to: sessionDir.appending(path: "transcript.txt"), atomically: true, encoding: .utf8)
    }

    /// Finds sessions orphaned by a crash/force-quit, mixes and saves each as
    /// a Recording so nothing is ever lost. Runs at launch.
    static func recoverOrphanedSessions(container: ModelContainer) async {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: inProgressDirectory, includingPropertiesForKeys: nil) else { return }
        let context = container.mainContext
        for dir in dirs where dir.hasDirectoryPath {
            let micURL = dir.appending(path: "mic.caf")
            guard fm.fileExists(atPath: micURL.path) else {
                try? fm.removeItem(at: dir)
                continue
            }
            let sysURL = dir.appending(path: "sys.caf")
            let meta = (try? Data(contentsOf: dir.appending(path: "meta.json")))
                .flatMap { try? JSONDecoder().decode(SessionMeta.self, from: $0) }
            do {
                let wavURL = fm.temporaryDirectory.appending(path: "fognote-recover-\(UUID().uuidString).wav")
                defer { try? fm.removeItem(at: wavURL) }
                try AudioFileMixer.mix(
                    trackA: micURL,
                    trackB: fm.fileExists(atPath: sysURL.path) ? sysURL : nil,
                    to: wavURL
                )
                let started = meta?.startedAt ?? .now
                let fileName = "Recovered \(started.formatted(.dateTime.year().month().day().hour().minute())).mp3"
                    .replacingOccurrences(of: ":", with: ".")
                let mp3URL = Recording.recordingsDirectory.appending(path: fileName)
                try await AudioFileMixer.encodeMP3(source: wavURL, destination: mp3URL)

                let note: Note
                if let uuid = meta?.noteUUID,
                   let existing = try? context.fetch(FetchDescriptor<Note>()).first(where: { $0.id == uuid }) {
                    note = existing
                } else {
                    note = Note(title: "Recovered Recording — \(started.formatted(date: .abbreviated, time: .shortened))")
                    context.insert(note)
                }
                let recording = Recording(
                    title: "Recovered — \(started.formatted(date: .abbreviated, time: .shortened))",
                    fileName: fileName
                )
                recording.duration = AudioFileMixer.duration(of: mp3URL)
                recording.createdAt = started
                recording.transcript = (try? String(contentsOf: dir.appending(path: "transcript.txt"), encoding: .utf8)) ?? ""
                recording.capturedSystemAudio = meta?.captureSystemAudio ?? false
                recording.note = note
                context.insert(recording)
                note.modifiedAt = .now
                try? context.save()
                try? fm.removeItem(at: dir)
            } catch {
                // Leave the session folder for the next attempt.
            }
        }
    }

    func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    var transcriptText: String {
        transcriptLines
            .filter { $0.isFinal }
            .map { "\($0.speaker): \($0.text)" }
            .joined(separator: "\n")
    }

    // MARK: - Internals

    private func teardownCapture() {
        timer?.invalidate()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        systemTap.onBuffer = nil
        systemTap.stop()
        micWriter = nil
        systemWriter = nil
        isPausedFlag.value = false
    }

    private func appendSegment(speaker: String, text: String, isFinal: Bool, start: Double) {
        guard !text.isEmpty else { return }
        if let index = transcriptLines.lastIndex(where: { $0.speaker == speaker && !$0.isFinal }) {
            transcriptLines[index].text = text
            transcriptLines[index].isFinal = isFinal
            transcriptLines[index].start = start
        } else {
            transcriptLines.append(TranscriptLine(speaker: speaker, text: text, isFinal: isFinal, start: start))
        }
        if isFinal { flushTranscript() }
    }

    /// Final, timed segments in spoken order (both speakers interleaved).
    var timedSegments: [TranscriptSegment] {
        transcriptLines
            .filter { $0.isFinal }
            .sorted { $0.start < $1.start }
            .map { TranscriptSegment(speaker: $0.speaker, text: $0.text, start: $0.start) }
    }

    private static let voiceThreshold: Float = 0.01

    private func registerMicActivity(level: Float, duration: Double) {
        micLevel = level
        if level > Self.voiceThreshold {
            talkSecondsMe += duration
            currentMonologueMe += duration
            longestMonologueMe = max(longestMonologueMe, currentMonologueMe)
        } else {
            currentMonologueMe = max(0, currentMonologueMe - duration * 0.5)
        }
    }

    private func registerSystemActivity(level: Float, duration: Double) {
        systemLevel = level
        if level > Self.voiceThreshold {
            talkSecondsThem += duration
            currentMonologueMe = 0
        }
    }
}

/// Lock-guarded bool usable from audio callbacks.
final class ThreadSafeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

extension AVAudioPCMBuffer {
    func rmsLevel() -> Float {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(frameLength)
        for i in 0..<count { sum += data[0][i] * data[0][i] }
        return (sum / Float(count)).squareRoot()
    }

    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        if let src = floatChannelData, let dst = copy.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                dst[channel].update(from: src[channel], count: Int(frameLength))
            }
        } else if let src = int16ChannelData, let dst = copy.int16ChannelData {
            for channel in 0..<Int(format.channelCount) {
                dst[channel].update(from: src[channel], count: Int(frameLength))
            }
        } else if let src = int32ChannelData, let dst = copy.int32ChannelData {
            for channel in 0..<Int(format.channelCount) {
                dst[channel].update(from: src[channel], count: Int(frameLength))
            }
        }
        return copy
    }
}
