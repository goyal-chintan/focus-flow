import Foundation

// Your focus rhythm (6 Nov 2026): not "how many minutes" but how you sit. A sitting is own-work
// blocks chained with less than 20 min between them. What it shows, from your own 4 weeks:
// how long you sit, what your good days look like next to the rest, how long you take to come
// back after a short or a long sitting, and what your gap answers say. Deliberate practice runs
// in sessions of about an hour or more with rest between (Ericsson, Krampe & Tesch-Römer, 1993);
// a slower return after longer sittings points at fatigue, a slow return after short ones at
// restarting (Steel, 2007, on task aversion). Pure.

struct FocusRhythm: Equatable, Sendable {
    struct Block: Equatable, Sendable {
        var start: Date
        var end: Date
        var focusedMinutes: Double
    }

    struct Sitting: Equatable, Sendable {
        var start: Date
        var end: Date
        var blocks: Int
        var focusedMinutes: Double
    }

    struct Finding: Equatable, Sendable, Identifiable {
        let id: String
        let symbol: String
        let title: String
        let sentence: String
    }

    let sittings: [Sitting]
    let blockMedian: Double?
    let singleBlockShare: Double?
    let sittingMedian: Double?
    /// Median longest sitting on days you met the day's target, and on the other days.
    let goodDayLongest: Double?
    let otherDayLongest: Double?
    let goodDays: Int
    let otherDays: Int
    /// Median minutes to the next sitting the same day, after a short (< 45 min) or a long one.
    let returnAfterShort: Double?
    let returnAfterLong: Double?
    /// Your gap answers (count and minutes), and big gaps with no answer yet.
    let reasons: [GapReason: (count: Int, minutes: Double)]
    let unlabeledGaps: Int

    static let chainMinutes = 20.0
    static let longSitting = 45.0

    static func == (a: FocusRhythm, b: FocusRhythm) -> Bool {
        a.sittings == b.sittings && a.unlabeledGaps == b.unlabeledGaps && a.goodDays == b.goodDays
    }

    static func sittings(_ blocks: [Block]) -> [Sitting] {
        var out: [Sitting] = []
        for b in blocks.sorted(by: { $0.start < $1.start }) {
            if var last = out.last, b.start.timeIntervalSince(last.end) / 60 < chainMinutes,
               Calendar.current.isDate(b.start, inSameDayAs: last.start) {
                last.end = max(last.end, b.end)
                last.blocks += 1
                last.focusedMinutes += b.focusedMinutes
                out[out.count - 1] = last
            } else {
                out.append(Sitting(start: b.start, end: b.end, blocks: 1, focusedMinutes: b.focusedMinutes))
            }
        }
        return out
    }

    /// `ledger`: day entries (for good days); `gaps`: big gaps with their answers.
    static func compute(blocks: [Block], ledger: [DayEntry], gaps: [DayAccount.Gap], calendar: Calendar = .current) -> FocusRhythm {
        let sittings = sittings(blocks)
        let byDay = Dictionary(grouping: sittings) { calendar.startOfDay(for: $0.start) }
        let goodDaySet = Set(ledger.filter { $0.verdict != .open && $0.targetMinutes > 0 && $0.ownMinutes >= Double($0.targetMinutes) }.map(\.day))
        let judged = Set(ledger.filter { $0.verdict != .open && $0.targetMinutes > 0 }.map(\.day))
        func longest(_ day: Date) -> Double { byDay[day]?.map(\.focusedMinutes).max() ?? 0 }
        let good = judged.filter { goodDaySet.contains($0) }
        let other = judged.filter { !goodDaySet.contains($0) && byDay[$0] != nil }

        var afterShort: [Double] = [], afterLong: [Double] = []
        for (_, list) in byDay {
            let sorted = list.sorted { $0.start < $1.start }
            for (i, s) in sorted.enumerated() where i + 1 < sorted.count {
                let gap = sorted[i + 1].start.timeIntervalSince(s.end) / 60
                if s.focusedMinutes >= longSitting { afterLong.append(gap) } else { afterShort.append(gap) }
            }
        }

        var reasons: [GapReason: (count: Int, minutes: Double)] = [:]
        for gap in gaps {
            guard let r = gap.reason else { continue }
            reasons[r, default: (0, 0)].count += 1
            reasons[r, default: (0, 0)].minutes += gap.minutes
        }
        func med(_ xs: [Double], min n: Int = 3) -> Double? { xs.count >= n ? CoachPatterns.median(xs) : nil }
        return FocusRhythm(
            sittings: sittings,
            blockMedian: med(blocks.map(\.focusedMinutes)),
            singleBlockShare: sittings.count >= 5 ? Double(sittings.filter { $0.blocks == 1 }.count) / Double(sittings.count) : nil,
            sittingMedian: med(sittings.map(\.focusedMinutes)),
            goodDayLongest: med(good.map(longest), min: 2),
            otherDayLongest: med(other.map(longest), min: 2),
            goodDays: good.count, otherDays: other.count,
            returnAfterShort: med(afterShort), returnAfterLong: med(afterLong),
            reasons: reasons,
            unlabeledGaps: gaps.filter { $0.reason == nil && $0.minutes >= 60 }.count
        )
    }

    /// The patterns worth a sentence, strongest first.
    var findings: [Finding] {
        var out: [Finding] = []
        if let share = singleBlockShare, let block = blockMedian, let sit = sittingMedian {
            out.append(Finding(id: "sittings", symbol: "chair",
                               title: "You sit for one block",
                               sentence: "\(pct(share)) of your sittings are a single block (median block \(m(block))), so a typical sitting is \(m(sit)) before you get up."))
        }
        if let good = goodDayLongest, let other = otherDayLongest, good >= other * 1.3 {
            out.append(Finding(id: "goodDays", symbol: "star",
                               title: "Your good days have one long sitting",
                               sentence: "On the \(goodDays) days you met your target, your longest sitting was \(m(good)); on the other \(otherDays), \(m(other)). The long sitting is what makes the day."))
        }
        if let short = returnAfterShort {
            if let long = returnAfterLong, long >= short * 1.5 {
                out.append(Finding(id: "fatigue", symbol: "battery.25",
                                   title: "Long sittings cost you a long recovery",
                                   sentence: "After a sitting of 45+ min you're back in \(m(long)); after a short one, \(m(short)). That looks like fatigue: a real break (away from the screen) after the second block brings you back sooner."))
            } else if short >= 45 {
                let compare = returnAfterLong.map { " (after a long one, \(m($0)))" } ?? ""
                out.append(Finding(id: "restart", symbol: "arrow.counterclockwise",
                                   title: "Restarting is the hard part",
                                   sentence: "Even after a short sitting you take \(m(short)) to start again\(compare). It isn't tiredness: it's the restart. Stay for a second block instead of getting up."))
            }
        }
        let notFine = reasons.filter { !$0.key.isFine }
        if let top = notFine.max(by: { $0.value.minutes < $1.value.minutes }), top.value.count >= 2 {
            out.append(Finding(id: "reason.\(top.key.rawValue)", symbol: "questionmark.bubble",
                               title: "Your gaps: \(top.key.title.lowercased())",
                               sentence: "You called \(top.value.count) gaps \"\(top.key.title.lowercased())\": \(m(top.value.minutes)) in 4 weeks."
                                   + (reasons.filter { $0.key.isFine }.isEmpty ? "" : " Family, rest and meals don't count against you.")))
        }
        if unlabeledGaps >= 2 {
            out.append(Finding(id: "unlabeled", symbol: "tag",
                               title: "\(unlabeledGaps) long gaps have no reason yet",
                               sentence: "Say what they were on Today, or click a day in Insights: family and rest are fine; tired, wasted time and side projects are what the coach can help with."))
        }
        return out
    }

    private func m(_ minutes: Double) -> String { FFFormatLite.duration(minutes) }
    private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
