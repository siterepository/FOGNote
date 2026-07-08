import Foundation
import AVFoundation
import SwiftLAME

/// Offline audio pipeline: mixes the mic + system tracks, encodes MP3,
/// and joins multiple MP3s into one file. Everything streams in chunks,
/// so hour-long calls never load fully into memory.
enum AudioFileMixer {
    static let workFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )!

    /// Reads any AVAudioFile-decodable file as 48kHz stereo Float32 chunks.
    final class ChunkReader {
        private let file: AVAudioFile
        private let converter: AVAudioConverter
        private var sourceDrained = false

        init?(url: URL) {
            guard let file = try? AVAudioFile(forReading: url),
                  let converter = AVAudioConverter(from: file.processingFormat, to: workFormat) else {
                return nil
            }
            self.file = file
            self.converter = converter
        }

        /// Next chunk of up to `frames` output frames; nil when exhausted.
        func next(frames: AVAudioFrameCount = 48000) -> AVAudioPCMBuffer? {
            guard let out = AVAudioPCMBuffer(pcmFormat: workFormat, frameCapacity: frames) else { return nil }
            var conversionError: NSError?
            let status = converter.convert(to: out, error: &conversionError) { [self] packets, outStatus in
                if sourceDrained {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard let inBuffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: min(packets, 16384)
                ) else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inBuffer)
                } catch {
                    sourceDrained = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    sourceDrained = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inBuffer
            }
            if status == .error { return nil }
            return out.frameLength > 0 ? out : nil
        }
    }

    private static func makeWAVWriter(url: URL) throws -> AVAudioFile {
        try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    /// Sum two source tracks (different lengths OK) into a stereo WAV.
    static func mix(trackA: URL, trackB: URL?, to wavURL: URL) throws {
        let writer = try makeWAVWriter(url: wavURL)
        let readerA = ChunkReader(url: trackA)
        let readerB = trackB.flatMap { ChunkReader(url: $0) }
        guard readerA != nil || readerB != nil else {
            throw NSError(domain: "FOGNote", code: 1, userInfo: [NSLocalizedDescriptionKey: "No readable audio tracks."])
        }

        var chunkA = readerA?.next()
        var chunkB = readerB?.next()
        while chunkA != nil || chunkB != nil {
            let frames = max(chunkA?.frameLength ?? 0, chunkB?.frameLength ?? 0)
            guard frames > 0, let out = AVAudioPCMBuffer(pcmFormat: workFormat, frameCapacity: frames) else { break }
            out.frameLength = frames
            for channel in 0..<2 {
                let dst = out.floatChannelData![channel]
                for i in 0..<Int(frames) {
                    var sample: Float = 0
                    if let a = chunkA, i < Int(a.frameLength) { sample += a.floatChannelData![channel][i] }
                    if let b = chunkB, i < Int(b.frameLength) { sample += b.floatChannelData![channel][i] }
                    dst[i] = max(-1, min(1, sample))
                }
            }
            try writer.write(from: out)
            chunkA = readerA?.next()
            chunkB = readerB?.next()
        }
    }

    /// Encode a WAV/CAF file to MP3 (192 kbps CBR) via LAME.
    static func encodeMP3(source: URL, destination: URL) async throws {
        let encoder = try SwiftLameEncoder(
            sourceUrl: source,
            configuration: LameConfiguration(
                sampleRate: .default,
                bitrateMode: .constant(192),
                quality: .standard
            ),
            destinationUrl: destination
        )
        try await encoder.encode(priority: .userInitiated)
    }

    /// Concatenate multiple audio files (MP3 decode is supported by AVAudioFile)
    /// into one MP3.
    static func join(files: [URL], to mp3URL: URL) async throws {
        let wavURL = FileManager.default.temporaryDirectory
            .appending(path: "fognote-join-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        // Scope the writer so the WAV is flushed/closed before LAME reads it.
        do {
            let writer = try makeWAVWriter(url: wavURL)
            for url in files {
                guard let reader = ChunkReader(url: url) else { continue }
                while let chunk = reader.next() {
                    try writer.write(from: chunk)
                }
            }
        }
        try await encodeMP3(source: wavURL, destination: mp3URL)
    }

    /// Duration in seconds of any decodable audio file.
    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Downsampled amplitude envelope for waveform display.
    static func waveform(of url: URL, buckets: Int = 400) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return [] }
        let framesPerBucket = max(1, Int(file.length) / buckets)
        var result: [Float] = []
        result.reserveCapacity(buckets)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerBucket)) else { return [] }
        while result.count < buckets {
            do { try file.read(into: buffer, frameCount: AVAudioFrameCount(framesPerBucket)) } catch { break }
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(data[0][i]))
            }
            result.append(peak)
        }
        let maxPeak = result.max() ?? 1
        return maxPeak > 0 ? result.map { $0 / maxPeak } : result
    }

    /// Export a time range of an audio file as a new MP3 (trim/excerpt).
    static func excerpt(source: URL, from start: TimeInterval, to end: TimeInterval, toMP3 mp3URL: URL) async throws {
        let wavURL = FileManager.default.temporaryDirectory
            .appending(path: "fognote-trim-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        do {
            guard let reader = ChunkReader(url: source) else {
                throw NSError(domain: "FOGNote", code: 11, userInfo: [NSLocalizedDescriptionKey: "Can't read audio file."])
            }
            let writer = try makeWAVWriter(url: wavURL)
            let sampleRate = workFormat.sampleRate
            let startFrame = Int(start * sampleRate)
            let endFrame = Int(end * sampleRate)
            var position = 0
            while position < endFrame, let chunk = reader.next() {
                let chunkStart = position
                let chunkEnd = position + Int(chunk.frameLength)
                position = chunkEnd
                if chunkEnd <= startFrame { continue }
                let sliceFrom = max(0, startFrame - chunkStart)
                let sliceTo = min(Int(chunk.frameLength), endFrame - chunkStart)
                guard sliceTo > sliceFrom,
                      let out = AVAudioPCMBuffer(pcmFormat: workFormat, frameCapacity: AVAudioFrameCount(sliceTo - sliceFrom)) else { continue }
                out.frameLength = AVAudioFrameCount(sliceTo - sliceFrom)
                for channel in 0..<2 {
                    out.floatChannelData![channel].update(from: chunk.floatChannelData![channel] + sliceFrom, count: sliceTo - sliceFrom)
                }
                try writer.write(from: out)
            }
        }
        try await encodeMP3(source: wavURL, destination: mp3URL)
    }
}
