import Testing
import Foundation
import AVFoundation
@testable import FOGNote

@MainActor @Suite struct SearchServiceTests {
    private func makeNote(title: String, body: String, tags: [FOGNote.Tag] = [], notebook: Notebook? = nil) -> Note {
        let note = Note(title: title, notebook: notebook)
        note.bodyPlainText = body
        note.tags = tags
        return note
    }

    @Test func freeTextMatchesTitleAndBody() {
        let a = makeNote(title: "Groceries", body: "milk eggs")
        let b = makeNote(title: "Work", body: "quarterly plan")
        let result = SearchService.filter(notes: [a, b], query: "milk")
        #expect(result.count == 1 && result[0].title == "Groceries")
    }

    @Test func tagFilter() {
        let tag = FOGNote.Tag(name: "urgent")
        let a = makeNote(title: "A", body: "", tags: [tag])
        let b = makeNote(title: "B", body: "")
        let result = SearchService.filter(notes: [a, b], query: "tag:urgent")
        #expect(result.count == 1 && result[0].title == "A")
    }

    @Test func intitleFilter() {
        let a = makeNote(title: "Roadmap 2026", body: "")
        let b = makeNote(title: "Notes", body: "roadmap mention")
        let result = SearchService.filter(notes: [a, b], query: "intitle:roadmap")
        #expect(result.count == 1 && result[0].title == "Roadmap 2026")
    }

    @Test func todoFilter() {
        let a = makeNote(title: "Tasks", body: "☐ buy milk")
        let b = makeNote(title: "Plain", body: "nothing here")
        let result = SearchService.filter(notes: [a, b], query: "todo:true")
        #expect(result.count == 1 && result[0].title == "Tasks")
    }
}

@MainActor @Suite struct LockServiceTests {
    @Test func lockRoundTrip() {
        let note = Note(title: "Secret")
        LockService.setLock(on: note, password: "hunter2")
        #expect(note.isLocked)
        #expect(LockService.verify(password: "hunter2", note: note))
        #expect(!LockService.verify(password: "wrong", note: note))
        LockService.removeLock(from: note)
        #expect(!note.isLocked && note.lockPasswordHash == nil)
    }
}

@MainActor @Suite struct ExportTests {
    @Test func markdownChecklistConversion() {
        let note = Note(title: "List")
        note.bodyPlainText = "☐ one\n☑ two"
        let md = ExportService.markdown(for: note)
        #expect(md.contains("- [ ] one"))
        #expect(md.contains("- [x] two"))
    }
}

@MainActor @Suite struct LinkParsingTests {
    @Test func extractsWikiLinks() {
        let titles = NoteInfoView.linkTitles(in: "see [[Roadmap]] and [[Meeting Notes]] ok")
        #expect(titles == ["Roadmap", "Meeting Notes"])
    }
}

@MainActor @Suite struct AudioMixerTests {
    private func makeSineWAV(seconds: Double, frequency: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "test-\(UUID().uuidString).wav")
        let format = AudioFileMixer.workFormat
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            for i in 0..<Int(frames) {
                buffer.floatChannelData![channel][i] = Float(sin(2.0 * .pi * frequency * Double(i) / format.sampleRate)) * 0.4
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test func mixTwoTracksAndEncodeMP3() async throws {
        let a = try makeSineWAV(seconds: 1.0, frequency: 440)
        let b = try makeSineWAV(seconds: 0.5, frequency: 880)
        let wav = FileManager.default.temporaryDirectory.appending(path: "mix-\(UUID().uuidString).wav")
        try AudioFileMixer.mix(trackA: a, trackB: b, to: wav)
        let mixDuration = AudioFileMixer.duration(of: wav)
        #expect(abs(mixDuration - 1.0) < 0.05)

        let mp3 = FileManager.default.temporaryDirectory.appending(path: "out-\(UUID().uuidString).mp3")
        try await AudioFileMixer.encodeMP3(source: wav, destination: mp3)
        #expect(FileManager.default.fileExists(atPath: mp3.path))
        #expect(AudioFileMixer.duration(of: mp3) > 0.9)

        let joined = FileManager.default.temporaryDirectory.appending(path: "joined-\(UUID().uuidString).mp3")
        try await AudioFileMixer.join(files: [mp3, mp3], to: joined)
        #expect(abs(AudioFileMixer.duration(of: joined) - 2 * AudioFileMixer.duration(of: mp3)) < 0.2)
        for url in [a, b, wav, mp3, joined] { try? FileManager.default.removeItem(at: url) }
    }

    @Test func talkRatio() {
        let recording = Recording(title: "t", fileName: "t.mp3")
        recording.talkSecondsMe = 30
        recording.talkSecondsThem = 70
        #expect(abs(recording.talkRatioMe - 0.3) < 0.001)
    }
}
