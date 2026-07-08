import Foundation
import Speech
import AVFoundation

/// One live transcription stream (SpeechAnalyzer, macOS 26, fully on-device).
/// FOGNote runs two of these during a call — one for the mic ("Me") and one
/// for system audio ("Them") — which yields speaker separation for free.
@MainActor
final class LiveTranscriber {
    let speaker: String
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var rawInput: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var tasks: [Task<Void, Never>] = []

    /// (speaker, text, isFinal) — volatile text replaces the previous volatile
    /// text for this speaker; final text should be appended.
    var onSegment: (@MainActor (String, String, Bool) -> Void)?

    init(speaker: String) {
        self.speaker = speaker
    }

    nonisolated static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            // @Sendable stops MainActor inference: TCC invokes this on a
            // background queue, and an isolated closure would SIGTRAP there.
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start(sourceFormat: AVAudioFormat) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw NSError(domain: "FOGNote", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "On-device transcription doesn't support the current language."
            ])
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw NSError(domain: "FOGNote", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "No compatible transcription audio format."
            ])
        }
        analyzerFormat = format

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = inputBuilder
        let (rawSequence, rawBuilder) = AsyncStream.makeStream(
            of: AVAudioPCMBuffer.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        self.rawInput = rawBuilder

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Conversion pump: raw source buffers -> analyzer format -> analyzer.
        let converter = AVAudioConverter(from: sourceFormat, to: format)
        tasks.append(Task { [weak self] in
            for await raw in rawSequence {
                guard let converter,
                      let out = AVAudioPCMBuffer(
                        pcmFormat: format,
                        frameCapacity: AVAudioFrameCount(
                            Double(raw.frameLength) * format.sampleRate / raw.format.sampleRate + 16
                        )
                      ) else { continue }
                var done = false
                _ = converter.convert(to: out, error: nil) { _, outStatus in
                    if done {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    done = true
                    outStatus.pointee = .haveData
                    return raw
                }
                if out.frameLength > 0 {
                    self?.inputBuilder?.yield(AnalyzerInput(buffer: out))
                }
            }
            self?.inputBuilder?.finish()
        })

        // Results pump.
        let speaker = speaker
        tasks.append(Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run {
                        self?.onSegment?(speaker, text, result.isFinal)
                    }
                }
            } catch {
                // Stream ended or transcription failed; recording continues.
            }
        })

        // Analysis driver.
        tasks.append(Task {
            _ = try? await analyzer.analyzeSequence(inputSequence)
        })
    }

    /// Safe to call from any thread/audio callback.
    nonisolated func feed(_ buffer: AVAudioPCMBuffer) {
        let box = AudioBufferBox(buffer: buffer)
        MainActor.assumeIsolatedOrQueue { [weak self] in
            self?.rawInput?.yield(box.buffer)
        }
    }

    func finish() async {
        rawInput?.finish()
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }
}

/// AVAudioPCMBuffer isn't Sendable; FOGNote only ever hands a deep copy to a
/// single consumer, so crossing isolation is safe here.
struct AudioBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

extension MainActor {
    /// Runs immediately if already on the main actor, otherwise hops.
    static func assumeIsolatedOrQueue(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }
}
