import Foundation

// Coach v8 §3.4 (docs/plans/2026-11-06-coach-v8-life-coach.md): the Insights page answers "how was
// my week?" against your own last 4 weeks. Monitoring progress works best when it is compared with
// your own baseline and shown often (Harkin et al., 2016). Pure; `TimerViewModel.yourWeek` feeds it.

struct WeekMeasures: Equatable, Sendable {
    /// Days in the span (7 for this week; for the baseline, the days with history).
    var days: Int
    var ownMinutes: Double
    /// Days on track (at least half the day's target, and 25 min: `DayVerdict`'s "did"), out of days with a target.
    var activeDays: Double
    var targetDays: Double
    var goalMetDays: Double
    var lostDays: Double
    /// App and site switches per hour inside blocks (hourly rollup only).
    var switchesPerHour: Double?
    /// Share of blocks that ran 5+ min past their length.
    var stretchRate: Double?
    /// Median minutes from a block's end to the next start in the same sitting.
    var medianReturnMinutes: Double?

    static let activeMinutes = 25.0
    static let minBlocksForRates = 4

    static func of(_ entries: [DayEntry], cycle: CoachCycleStats?, switches: (count: Int, blockHours: Double)?) -> WeekMeasures {
        let targeted = entries.filter { $0.targetMinutes > 0 }
        return WeekMeasures(
            days: entries.count,
            ownMinutes: entries.map(\.ownMinutes).reduce(0, +),
            activeDays: Double(targeted.filter { $0.ownMinutes >= DayVerdict.didMinutes(targetMinutes: $0.targetMinutes) }.count),
            targetDays: Double(targeted.count),
            goalMetDays: Double(targeted.filter { $0.ownMinutes >= Double($0.targetMinutes) }.count),
            lostDays: Double(entries.filter { $0.verdict == .unplannedLost }.count),
            switchesPerHour: switches.flatMap { $0.blockHours >= 1 ? Double($0.count) / $0.blockHours : nil },
            stretchRate: cycle.flatMap { $0.blocks >= minBlocksForRates ? Double($0.stretchedBlocks) / Double($0.blocks) : nil },
            medianReturnMinutes: cycle.flatMap { $0.gaps.count >= 3 ? $0.medianGap : nil }
        )
    }

    /// The same measures per 7 days, so 4 weeks of baseline compare with one week.
    func perWeek() -> WeekMeasures {
        guard days > 0 else { return self }
        let scale = 7 / Double(days)
        var w = self
        w.ownMinutes *= scale; w.activeDays *= scale; w.targetDays *= scale; w.goalMetDays *= scale; w.lostDays *= scale
        w.days = 7
        return w
    }
}

struct WeekTrend: Equatable, Sendable, Identifiable {
    enum Direction: String, Sendable { case better, worse, same, unknown }

    let id: String
    let title: String
    let value: String
    /// "avg 5h 10m".
    let baseline: String?
    let direction: Direction
    /// "+48%", "−1", "+12 pts".
    let delta: String?
}

struct YourWeek: Equatable, Sendable {
    enum Verdict: String, Sendable { case better, same, worse, firstWeek }

    let days: [DayEntry]
    let span: String
    let verdict: Verdict
    let headline: String
    let line: String
    let trends: [WeekTrend]
    let this: WeekMeasures
    let baseline: WeekMeasures?

    static let baselineDays = 28
    /// A baseline needs at least a week of history.
    static let minBaselineDays = 7

    /// `entries`: the ledger oldest first, ending today (35 days). `firstDay`: the first day with
    /// any history, so empty days before you started don't drag the average down.
    static func build(entries: [DayEntry], firstDay: Date?, thisCycle: CoachCycleStats?, baselineCycle: CoachCycleStats?,
                      thisSwitches: (count: Int, blockHours: Double)?, baselineSwitches: (count: Int, blockHours: Double)?,
                      calendar: Calendar = .current) -> YourWeek {
        let week = Array(entries.suffix(7))
        let prior = Array(entries.dropLast(7).suffix(baselineDays)).filter { entry in
            firstDay.map { entry.day >= calendar.startOfDay(for: $0) } ?? false
        }
        let this = WeekMeasures.of(week, cycle: thisCycle, switches: thisSwitches)
        let base = prior.count >= minBaselineDays ? WeekMeasures.of(prior, cycle: baselineCycle, switches: baselineSwitches).perWeek() : nil

        let verdict = verdictOf(week: week, prior: prior, hasBaseline: base != nil)
        let headline: String
        switch verdict {
        case .better: headline = "Better than your last \(weeksLabel(prior.count))."
        case .worse: headline = "Below your last \(weeksLabel(prior.count))."
        case .same: headline = "About the same as your last \(weeksLabel(prior.count))."
        case .firstWeek: headline = "Your first week with the day ledger: no comparison yet."
        }
        var parts = ["\(FFFormatLite.duration(this.ownMinutes)) own work" + (base.map { " (avg \(FFFormatLite.duration($0.ownMinutes)))" } ?? "")]
        if this.targetDays > 0 { parts.append("goal met \(Int(this.goalMetDays)) of \(Int(this.targetDays)) days") }
        return YourWeek(
            days: week, span: spanLabel(week, calendar: calendar), verdict: verdict, headline: headline,
            line: parts.joined(separator: " · "), trends: trends(this: this, base: base), this: this, baseline: base
        )
    }

    /// Each day of this week against the mean of the same day type in the baseline (a leave day
    /// is compared with leave days). Today counts only once it is no longer open.
    static func verdictOf(week: [DayEntry], prior: [DayEntry], hasBaseline: Bool) -> Verdict {
        guard hasBaseline else { return .firstWeek }
        let overall = prior.isEmpty ? 0 : prior.map(\.ownMinutes).reduce(0, +) / Double(prior.count)
        let byType = Dictionary(grouping: prior, by: \.type).compactMapValues { days -> Double? in
            days.count >= 2 ? days.map(\.ownMinutes).reduce(0, +) / Double(days.count) : nil
        }
        let judged = week.filter { $0.verdict != .open && $0.type != .sick }
        let actual = judged.map(\.ownMinutes).reduce(0, +)
        let expected = judged.map { byType[$0.type] ?? overall }.reduce(0, +)
        guard expected >= 30 else { return actual >= 60 ? .better : .same }
        let ratio = actual / expected
        if ratio >= 1.15 { return .better }
        if ratio <= 0.85 { return .worse }
        return .same
    }

    static func trends(this: WeekMeasures, base: WeekMeasures?) -> [WeekTrend] {
        func relative(_ now: Double, _ then: Double, higherIsBetter: Bool, threshold: Double = 0.1) -> (WeekTrend.Direction, String?) {
            guard then > 0 else { return (now > 0 && higherIsBetter ? .better : .unknown, nil) }
            let change = (now - then) / then
            let text = "\(change >= 0 ? "+" : "−")\(Int((abs(change) * 100).rounded()))%"
            if abs(change) < threshold { return (.same, text) }
            return ((change > 0) == higherIsBetter ? .better : .worse, text)
        }
        func absolute(_ now: Double, _ then: Double, higherIsBetter: Bool, threshold: Double, unit: String = "") -> (WeekTrend.Direction, String?) {
            let diff = now - then
            let rounded = unit == " pts" ? Int((abs(diff) * 100).rounded()) : Int(abs(diff).rounded())
            let text = "\(diff >= 0 ? "+" : "−")\(rounded)\(unit)"
            if abs(diff) < threshold { return (.same, text) }
            return ((diff > 0) == higherIsBetter ? .better : .worse, text)
        }
        var out: [WeekTrend] = []
        let own = base.map { relative(this.ownMinutes, $0.ownMinutes, higherIsBetter: true) }
        out.append(WeekTrend(id: "own", title: "Own work", value: FFFormatLite.duration(this.ownMinutes),
                             baseline: base.map { "avg \(FFFormatLite.duration($0.ownMinutes))" }, direction: own?.0 ?? .unknown, delta: own?.1))
        let days = base.map { absolute(this.activeDays, $0.activeDays, higherIsBetter: true, threshold: 0.75) }
        out.append(WeekTrend(id: "consistency", title: "Days on track", value: "\(Int(this.activeDays))/\(Int(this.targetDays))",
                             baseline: base.map { String(format: "avg %.1f", $0.activeDays) }, direction: days?.0 ?? .unknown, delta: days?.1))
        let lost = base.map { absolute(this.lostDays, $0.lostDays, higherIsBetter: false, threshold: 0.75) }
        out.append(WeekTrend(id: "lost", title: "Unplanned & lost", value: "\(Int(this.lostDays))",
                             baseline: base.map { String(format: "avg %.1f", $0.lostDays) }, direction: lost?.0 ?? .unknown, delta: lost?.1))
        let switches: (WeekTrend.Direction, String?)? = this.switchesPerHour.flatMap { now in base?.switchesPerHour.map { relative(now, $0, higherIsBetter: false) } }
        out.append(WeekTrend(id: "switches", title: "Switches per block hour", value: this.switchesPerHour.map { "\(Int($0.rounded()))" } ?? "—",
                             baseline: base?.switchesPerHour.map { "avg \(Int($0.rounded()))" }, direction: switches?.0 ?? .unknown, delta: switches?.1))
        let stretch: (WeekTrend.Direction, String?)? = this.stretchRate.flatMap { now in base?.stretchRate.map { absolute(now, $0, higherIsBetter: false, threshold: 0.1, unit: " pts") } }
        out.append(WeekTrend(id: "stretch", title: "Blocks run over", value: this.stretchRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                             baseline: base?.stretchRate.map { "avg \(Int(($0 * 100).rounded()))%" }, direction: stretch?.0 ?? .unknown, delta: stretch?.1))
        let back: (WeekTrend.Direction, String?)? = this.medianReturnMinutes.flatMap { now in base?.medianReturnMinutes.map { relative(now, $0, higherIsBetter: false, threshold: 0.2) } }
        out.append(WeekTrend(id: "return", title: "Back to the next block", value: this.medianReturnMinutes.map { "\(Int($0.rounded()))m" } ?? "—",
                             baseline: base?.medianReturnMinutes.map { "avg \(Int($0.rounded()))m" }, direction: back?.0 ?? .unknown, delta: back?.1))
        return out
    }

    static func weeksLabel(_ days: Int) -> String {
        let weeks = max(1, Int((Double(days) / 7).rounded()))
        return weeks == 1 ? "week" : "\(weeks) weeks"
    }

    /// "31 Oct – 6 Nov".
    static func spanLabel(_ days: [DayEntry], calendar: Calendar) -> String {
        guard let first = days.first?.day, let last = days.last?.day else { return "" }
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
}

/// Duration text without importing the SwiftUI design system ("7h 40m", "45m").
enum FFFormatLite {
    static func duration(_ minutes: Double) -> String {
        let total = Int(max(0, minutes).rounded())
        let h = total / 60, m = total % 60
        if h > 0 && m == 0 { return "\(h)h" }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
