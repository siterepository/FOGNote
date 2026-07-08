import SwiftUI
import SwiftData
import Charts

/// Sales insights dashboard: call volume, talk-ratio trend, call scores,
/// note activity. All local, all from data FOGNote already collects.
struct InsightsView: View {
    @Query private var notes: [Note]
    @Query private var recordings: [Recording]

    private var calendar: Calendar { .current }

    private struct WeekBucket: Identifiable {
        let id: Date
        let calls: Int
        let notes: Int
    }

    private var weeklyBuckets: [WeekBucket] {
        let start = calendar.date(byAdding: .weekOfYear, value: -7, to: calendar.startOfDay(for: .now))!
        var buckets: [Date: (calls: Int, notes: Int)] = [:]
        for offset in 0..<8 {
            let week = calendar.date(byAdding: .weekOfYear, value: offset, to: start)!
            let anchor = calendar.dateInterval(of: .weekOfYear, for: week)!.start
            buckets[anchor] = (0, 0)
        }
        for recording in recordings {
            let anchor = calendar.dateInterval(of: .weekOfYear, for: recording.createdAt)!.start
            if buckets[anchor] != nil { buckets[anchor]!.calls += 1 }
        }
        for note in notes where !note.isTemplate && !note.isTrashed {
            let anchor = calendar.dateInterval(of: .weekOfYear, for: note.createdAt)!.start
            if buckets[anchor] != nil { buckets[anchor]!.notes += 1 }
        }
        return buckets.keys.sorted().map { WeekBucket(id: $0, calls: buckets[$0]!.calls, notes: buckets[$0]!.notes) }
    }

    private struct CallPoint: Identifiable {
        let id: PersistentIdentifier
        let date: Date
        let ratio: Double
        let score: Int?
    }

    private var callPoints: [CallPoint] {
        recordings
            .filter { $0.talkSecondsMe + $0.talkSecondsThem > 0 }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(20)
            .map { recording in
                CallPoint(
                    id: recording.persistentModelID,
                    date: recording.createdAt,
                    ratio: recording.talkRatioMe * 100,
                    score: Self.score(from: recording.summary)
                )
            }
    }

    static func score(from summary: String) -> Int? {
        guard let range = summary.range(of: #"Call score: (\d+)/100"#, options: .regularExpression) else { return nil }
        return Int(summary[range].dropFirst("Call score: ".count).dropLast(4))
    }

    private var avgScore: Int? {
        let scores = recordings.compactMap { Self.score(from: $0.summary) }
        return scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
    }

    private var avgRatio: Int? {
        let points = callPoints
        guard !points.isEmpty else { return nil }
        return Int(points.map(\.ratio).reduce(0, +) / Double(points.count))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 22) {
                    tile("Calls (8 wks)", "\(weeklyBuckets.map(\.calls).reduce(0, +))", "waveform.circle")
                    tile("Avg Talk %", avgRatio.map { "\($0)%" } ?? "—", "person.wave.2", hint: "Benchmark: 43%")
                    tile("Avg Call Score", avgScore.map { "\($0)/100" } ?? "—", "gauge.with.needle")
                    tile("Notes", "\(notes.filter { !$0.isTemplate && !$0.isTrashed }.count)", "note.text")
                }

                GroupBox("Activity per Week") {
                    Chart(weeklyBuckets) { bucket in
                        BarMark(
                            x: .value("Week", bucket.id, unit: .weekOfYear),
                            y: .value("Calls", bucket.calls)
                        )
                        .foregroundStyle(Color.fogAccent)
                        .position(by: .value("Kind", "Calls"))
                        BarMark(
                            x: .value("Week", bucket.id, unit: .weekOfYear),
                            y: .value("Notes", bucket.notes)
                        )
                        .foregroundStyle(Color.fogSecondary.opacity(0.7))
                        .position(by: .value("Kind", "Notes"))
                    }
                    .chartLegend(.visible)
                    .frame(height: 180)
                    .padding(6)
                }

                GroupBox("Talk-Time Ratio — last 20 calls (lower is usually better)") {
                    Chart {
                        RuleMark(y: .value("Benchmark", 43))
                            .foregroundStyle(.tertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .trailing) {
                                Text("43%").font(.caption2).foregroundStyle(.tertiary)
                            }
                        ForEach(callPoints) { point in
                            LineMark(x: .value("Call", point.date), y: .value("You %", point.ratio))
                                .foregroundStyle(Color.fogAccent)
                            PointMark(x: .value("Call", point.date), y: .value("You %", point.ratio))
                                .foregroundStyle(point.ratio > 60 ? Color.fogWarn : Color.fogAccent)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 160)
                    .padding(6)
                }

                if callPoints.contains(where: { $0.score != nil }) {
                    GroupBox("Call Scores") {
                        Chart(callPoints.filter { $0.score != nil }) { point in
                            BarMark(x: .value("Call", point.date, unit: .day), y: .value("Score", point.score ?? 0))
                                .foregroundStyle(Color.fogSecondary)
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 140)
                        .padding(6)
                    }
                }
            }
            .padding(18)
        }
        .frame(minWidth: 640, minHeight: 560)
        .navigationTitle("Insights")
    }

    private func tile(_ label: String, _ value: String, _ symbol: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
