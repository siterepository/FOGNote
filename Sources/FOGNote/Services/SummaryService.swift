import Foundation
import FoundationModels

/// On-device AI (Apple Foundation Models) sales-call summaries.
/// Template follows what reps paste into CRMs: BANT qualification,
/// discovery insights, objections, action items, next steps, call score.
@Generable
struct SalesCallSummary {
    @Guide(description: "2-3 sentence plain-language overview of the call")
    var overview: String

    @Guide(description: "Budget: amounts or constraints discussed, or 'Not discussed'")
    var budget: String

    @Guide(description: "Authority: decision maker names and evaluation process, or 'Not discussed'")
    var authority: String

    @Guide(description: "Need: the core business problems driving this deal, or 'Not discussed'")
    var need: String

    @Guide(description: "Timeline: decision dates or urgency signals, or 'Not discussed'")
    var timeline: String

    @Guide(description: "Prospect pain points in their own words", .maximumCount(6))
    var painPoints: [String]

    @Guide(description: "Objections or concerns raised and how they were handled", .maximumCount(6))
    var objections: [String]

    @Guide(description: "Competitors or alternative solutions mentioned", .maximumCount(4))
    var competitorMentions: [String]

    @Guide(description: "Concrete action items with owner (Me/Them) and any deadline", .maximumCount(8))
    var actionItems: [String]

    @Guide(description: "The agreed next step and when it happens")
    var nextSteps: String

    @Guide(description: "Overall buyer sentiment", .anyOf(["positive", "neutral", "negative", "mixed"]))
    var sentiment: String

    @Guide(description: "Call quality score judged on discovery depth, objection handling, and next-step clarity", .range(1...100))
    var callScore: Int
}

@MainActor
enum SummaryService {
    enum AvailabilityStatus {
        case ready
        case unavailable(String)
    }

    static func availability() -> AvailabilityStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Enable Apple Intelligence in System Settings to get AI summaries.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence model is still downloading — try again shortly.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac can't run Apple Intelligence; AI summaries are unavailable.")
        default:
            return .unavailable("On-device AI is unavailable right now.")
        }
    }

    /// Full pipeline: chunks long transcripts, generates the structured
    /// summary, and renders CRM-ready markdown.
    static func summarize(recording: Recording) async throws -> String {
        let transcript = recording.transcript
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "FOGNote", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "No transcript to summarize."
            ])
        }
        if case .unavailable(let reason) = availability() {
            throw NSError(domain: "FOGNote", code: 6, userInfo: [NSLocalizedDescriptionKey: reason])
        }

        let condensed = try await condenseIfNeeded(transcript)
        let session = LanguageModelSession {
            """
            You are a sales-call analyst. You extract accurate, specific facts from \
            call transcripts between "Me" (the sales rep) and "Them" (the prospect). \
            Never invent details; write "Not discussed" when the transcript lacks them.
            """
        }
        let response = try await session.respond(
            to: "Analyze this sales call transcript:\n\n\(condensed)",
            generating: SalesCallSummary.self
        )
        return render(summary: response.content, recording: recording)
    }

    /// Draft a follow-up email that quotes the prospect's own language.
    static func followUpEmail(recording: Recording) async throws -> String {
        if case .unavailable(let reason) = availability() {
            throw NSError(domain: "FOGNote", code: 6, userInfo: [NSLocalizedDescriptionKey: reason])
        }
        let condensed = try await condenseIfNeeded(recording.transcript)
        let session = LanguageModelSession {
            """
            You write short, concrete sales follow-up emails. Reference the prospect's \
            exact words where possible, confirm agreed next steps, and keep it under \
            180 words. No fluff, no "I hope this finds you well".
            """
        }
        let response = try await session.respond(
            to: "Draft the follow-up email for this call transcript:\n\n\(condensed)\n\nExisting summary:\n\(recording.summary.prefix(1500))"
        )
        return response.content
    }

    // MARK: - Long-transcript handling

    /// The on-device model has a small context window; map-reduce long calls.
    private static func condenseIfNeeded(_ transcript: String, limit: Int = 9000) async throws -> String {
        guard transcript.count > limit else { return transcript }
        let chunks = stride(from: 0, to: transcript.count, by: limit).map { offset -> String in
            let start = transcript.index(transcript.startIndex, offsetBy: offset)
            let end = transcript.index(start, offsetBy: limit, limitedBy: transcript.endIndex) ?? transcript.endIndex
            return String(transcript[start..<end])
        }
        var digests: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let session = LanguageModelSession {
                "You condense sales-call transcript excerpts into dense factual notes, keeping every number, name, objection, commitment, and quote."
            }
            let response = try await session.respond(
                to: "Condense part \(index + 1)/\(chunks.count) of this call transcript into notes:\n\n\(chunk)"
            )
            digests.append(response.content)
        }
        return digests.joined(separator: "\n\n")
    }

    // MARK: - Rendering

    private static func render(summary: SalesCallSummary, recording: Recording) -> String {
        let ratio = Int((recording.talkRatioMe * 100).rounded())
        var lines: [String] = []
        lines.append("## Call Summary — \(recording.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append(summary.overview)
        lines.append("")
        lines.append("**Qualification (BANT)**")
        lines.append("- Budget: \(summary.budget)")
        lines.append("- Authority: \(summary.authority)")
        lines.append("- Need: \(summary.need)")
        lines.append("- Timeline: \(summary.timeline)")
        if !summary.painPoints.isEmpty {
            lines.append("")
            lines.append("**Pain Points**")
            lines.append(contentsOf: summary.painPoints.map { "- \($0)" })
        }
        if !summary.objections.isEmpty {
            lines.append("")
            lines.append("**Objections & Concerns**")
            lines.append(contentsOf: summary.objections.map { "- \($0)" })
        }
        if !summary.competitorMentions.isEmpty {
            lines.append("")
            lines.append("**Competitor Mentions**")
            lines.append(contentsOf: summary.competitorMentions.map { "- \($0)" })
        }
        if !summary.actionItems.isEmpty {
            lines.append("")
            lines.append("**Action Items**")
            lines.append(contentsOf: summary.actionItems.map { "☐ \($0)" })
        }
        lines.append("")
        lines.append("**Next Steps:** \(summary.nextSteps)")
        lines.append("")
        lines.append("**Call Metrics**")
        lines.append("- Talk time: Me \(ratio)% / Them \(100 - ratio)%")
        lines.append("- Sentiment: \(summary.sentiment)")
        lines.append("- Call score: \(summary.callScore)/100")
        return lines.joined(separator: "\n")
    }
}
