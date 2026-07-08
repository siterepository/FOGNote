import Foundation
import SwiftData

/// One timed line of a call transcript.
struct TranscriptSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var speaker: String
    var text: String
    /// Seconds from the start of the recording.
    var start: Double
}

/// A call/voice recording attached to a note. Audio lives on disk in
/// Application Support/FOGNote/Recordings; the model stores the file name.
@Model
final class Recording {
    var id: UUID = UUID()
    var title: String = ""
    var fileName: String = ""
    var createdAt: Date = Date.now
    var duration: TimeInterval = 0
    /// Full transcript, lines prefixed with speaker labels ("Me:" / "Them:").
    var transcript: String = ""
    /// AI-generated sales summary (markdown).
    var summary: String = ""
    /// Seconds each side spoke, for talk-time ratio coaching.
    var talkSecondsMe: Double = 0
    var talkSecondsThem: Double = 0
    /// Timestamps (seconds) the user bookmarked during the call.
    var bookmarks: [Double] = []
    /// Timed transcript segments (JSON-encoded [TranscriptSegment]).
    var segmentsData: Data = Data()
    /// Cached waveform envelope (Float32 array bytes) so the Studio never
    /// re-decodes hours of audio just to draw the wave.
    var waveformData: Data = Data()
    var capturedSystemAudio: Bool = false
    var note: Note?

    init(title: String, fileName: String) {
        self.title = title
        self.fileName = fileName
    }

    var fileURL: URL {
        Recording.recordingsDirectory.appending(path: fileName)
    }

    var talkRatioMe: Double {
        let total = talkSecondsMe + talkSecondsThem
        guard total > 0 else { return 0 }
        return talkSecondsMe / total
    }

    var segments: [TranscriptSegment] {
        get { (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? [] }
        set { segmentsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var waveform: [Float] {
        get {
            waveformData.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self))
            }
        }
        set {
            waveformData = newValue.withUnsafeBufferPointer { Data(buffer: $0) }
        }
    }

    static var recordingsDirectory: URL {
        let dir = URL.applicationSupportDirectory
            .appending(path: "FOGNote", directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
