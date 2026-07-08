import Foundation
import Vision
import AppKit

/// On-device OCR for image attachments (Vision). Extracted text is stored on
/// the attachment and searched alongside note bodies — Evernote-style
/// "search inside your screenshots/receipts/whiteboards".
enum OCRService {
    nonisolated static func recognizeText(in imageData: Data) async -> String {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
