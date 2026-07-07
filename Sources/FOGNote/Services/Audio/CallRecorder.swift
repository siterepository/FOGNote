import Foundation
import AVFoundation
import SwiftUI

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
    enum State: Equatable {
        case idle
        case recording
        case paused
        case processing(String)
        case failed(String)
    }

    struct TranscriptLine: Identifiable, Equatable {
        let id = UUID()
        var speaker: String
        var text: String
        var isFinal: Bool
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
    private var isPausedFlag = ThreadSafeFlag()

    var isActive: Bool {
        state == .recording || state == .paused
    }

    // MARK: - Start

    func start() async {
        guard state == .idle else { return }
        transcriptLines = []
        bookmarks = []
        talkSecondsMe = 0
        talkSecondsThem = 0
        longestMonologueMe = 0
        currentMonologueMe = 0
        pausedAccumulated = 0
        elapsed = 0

        let temp = FileManager.default.temporaryDirectory
        let stamp = UUID().uuidString
        let micURL = temp.appending(path: "fognote-mic-\(stamp).caf")
        let sysURL = temp.appending(path: "fognote-sys-\(stamp).caf")
        micTempURL = micURL
        systemTempURL = captureSystemAudio ? sysURL : nil

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
                    mic.onSegment = { [weak self] speaker, text, isFinal in
                        self?.appendSegment(speaker: speaker, text: text, isFinal: isFinal)
                    }
                    try? await mic.start(sourceFormat: micFormat)
                    micTranscriber = mic
                }
            }

            let paused = isPausedFlag
            let micTranscriber = micTranscriber
            input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
                guard !paused.value else { return }
                micWriter.write(buffer)
                let level = buffer.rmsLevel()
                if let copy = buffer.deepCopy() {
                    micTranscriber?.feed(copy)
                }
                Task { @MainActor [weak self] in
                    self?.registerMicActivity(level: level, duration: Double(buffer.frameLength) / micFormat.sampleRate)
                }
            }
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
                        sys.onSegment = { [weak self] speaker, text, isFinal in
                            self?.appendSegment(speaker: speaker, text: text, isFinal: isFinal)
                        }
                        try? await sys.start(sourceFormat: tapFormat)
                        systemTranscriber = sys
                    }
                    let systemTranscriber = systemTranscriber
                    systemTap.onBuffer = { [weak self] buffer in
                        guard !paused.value else { return }
                        systemWriter.write(buffer)
                        let level = buffer.rmsLevel()
                        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                        if let copy = buffer.deepCopy() {
                            systemTranscriber?.feed(copy)
                        }
                        Task { @MainActor [weak self] in
                            self?.registerSystemActivity(level: level, duration: duration)
                        }
                    }
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
            try? FileManager.default.removeItem(at: micTempURL)
            if let systemTempURL { try? FileManager.default.removeItem(at: systemTempURL) }

            state = .idle
            return (fileName, duration)
        } catch {
            state = .failed("Audio processing failed: \(error.localizedDescription)")
            return nil
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

    private func appendSegment(speaker: String, text: String, isFinal: Bool) {
        guard !text.isEmpty else { return }
        if let index = transcriptLines.lastIndex(where: { $0.speaker == speaker && !$0.isFinal }) {
            if isFinal {
                transcriptLines[index].text = text
                transcriptLines[index].isFinal = true
            } else {
                transcriptLines[index].text = text
            }
        } else {
            transcriptLines.append(TranscriptLine(speaker: speaker, text: text, isFinal: isFinal))
        }
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
