import Foundation

// Coach v8 §3.4 "Do this next": at most three recommendations from a rule library over your own
// ledger, each with your evidence, one Apply action and a follow-up a week later (worked / didn't /
// not tried). Implementation intentions ("at 10:00 on Saturday I will…") roughly double follow-
// through (Gollwitzer & Sheeran, 2006), so most actions put a time on the calendar. Pure.

enum LifeRecKind: String, Codable, CaseIterable, Sendable {
    case neverMissTwice, weekendPlan, leaveTarget, targetMiss, landOnTime, breakLanding, windowsFit, appPull, derailerHour

    /// The follow-up measure: higher is better?
    var higherIsBetter: Bool {
        switch self {
        case .weekendPlan, .leaveTarget, .targetMiss: true
        default: false
        }
    }

    /// Windows, app roles and derailer hours have no week-over-week measure: they show as applied.
    var isMeasured: Bool {
        switch self {
        case .windowsFit, .appPull, .derailerHour: false
        default: true
        }
    }

    /// Whether the measure is a share (shown as %), else minutes.
    var metricIsRate: Bool {
        switch self {
        case .weekendPlan, .targetMiss, .neverMissTwice, .landOnTime: true
        default: false
        }
    }
}

enum LifeAction: Equatable, Sendable {
    /// Planned blocks at these times (implementation intentions).
    case planBlocks([Date])
    case setTarget(DayType, Int)
    case blockLength(Int)
    case breakLength(Int)
    case useObservedWindows
    case appRole(key: String, name: String, projectID: UUID, role: AppRole)
    /// Count an app or site as a distraction everywhere.
    case markPull(key: String, name: String)
    /// The workday target is the Goals tab's daily goal.
    case openGoals
}

struct LifeRecommendation: Equatable, Sendable, Identifiable {
    let id: String
    let kind: LifeRecKind
    let title: String
    let evidence: String
    let impact: String
    let actionTitle: String
    let action: LifeAction
    /// 0–1: how much it would change your week, and how sure the evidence is.
    let weight: Double
    let confidence: Double

    var score: Double { weight * confidence }
}

/// Everything the library looks at. The view model fills it from the store.
struct LifeRecInput: Sendable {
    var now: Date
    /// The ledger, oldest first, ending today (35 days).
    var entries: [DayEntry]
    var cycle: CoachCycleStats
    var regularMinutes: Int
    var naturalLength: Int?
    /// Median actual break and the suggested one, in minutes, with how many breaks.
    var breaks: (actual: Double, suggested: Double, count: Int)?
    var windowFit: (observed: String, covered: Int, starts: Int)?
    var appPull: (key: String, name: String, projectID: UUID, projectName: String, minutes: Double, days: Int)?
    var derailer: (key: String, name: String, minutes: Double, fromHour: Int, toHour: Int, isYourRule: Bool)?
    /// Your targets per day type (unset types are absent).
    var targets: [DayType: Int]
    /// Today's resolved daily goal in minutes (what an unset type follows).
    var goalMinutes: Int
    /// When to put a block on a day off (your usual first start on free days).
    var freeDayHour: Int
    /// The coming weekend's days with no plan yet.
    var unplannedWeekend: [Date]
    /// A start time for a block today (nil: too late today).
    var todaySlot: Date?
    var hasPlanToday: Bool
    var calendar: Calendar = .current
}

enum LifeRecommendations {
    static let maxShown = 3

    static func all(_ input: LifeRecInput) -> [LifeRecommendation] {
        [neverMissTwice(input), weekendPlan(input), leaveTarget(input), targetMiss(input), landOnTime(input),
         breakLanding(input), windowsFit(input), appPull(input), derailerHour(input)].compactMap { $0 }
    }

    /// Ranked by weight × confidence, lowered when shown in the last week without an answer;
    /// applied (21 days) and dismissed (14 days) ones wait.
    static func ranked(_ recs: [LifeRecommendation], records: [String: LifeRecRecord], now: Date) -> [LifeRecommendation] {
        let day: TimeInterval = 86_400
        return recs.filter { rec in
            guard let record = records[rec.id] else { return true }
            if let applied = record.appliedAt, now.timeIntervalSince(applied) < 21 * day { return false }
            if let dismissed = record.dismissedAt, now.timeIntervalSince(dismissed) < 14 * day { return false }
            return true
        }
        .map { rec -> (LifeRecommendation, Double) in
            let stale = records[rec.id]?.firstShownAt.map { now.timeIntervalSince($0) > 7 * day } ?? false
            return (rec, rec.score * (stale ? 0.7 : 1))
        }
        .sorted { $0.1 > $1.1 }
        .prefix(maxShown)
        .map(\.0)
    }

    // MARK: Rules

    private static func past(_ input: LifeRecInput) -> [DayEntry] {
        input.entries.filter { $0.verdict != .open }.suffix(28)
    }

    static func isMiss(_ e: DayEntry) -> Bool {
        e.targetMinutes > 0 && e.ownMinutes < WeekMeasures.activeMinutes
    }

    /// Lally et al. (2010): one missed day does not hurt a habit; a run of them does.
    static func neverMissTwice(_ input: LifeRecInput) -> LifeRecommendation? {
        guard let today = input.entries.last, today.verdict == .open, today.targetMinutes > 0, !input.hasPlanToday,
              let yesterday = input.entries.dropLast().last, isMiss(yesterday), let slot = input.todaySlot else { return nil }
        let misses = past(input).filter(isMiss)
        let twice = zip(input.entries, input.entries.dropFirst()).filter { isMiss($0) && isMiss($1) && $1.verdict != .open }.count
        let evidence = twice > 0
            ? "Yesterday had no own work. In 4 weeks, \(twice) of your \(misses.count) misses ran into a second day."
            : "Yesterday had no own work. One miss is fine; two in a row is where a habit slips."
        return LifeRecommendation(
            id: LifeRecKind.neverMissTwice.rawValue, kind: .neverMissTwice, title: "Don't miss twice",
            evidence: evidence, impact: "A short block today keeps the chain.",
            actionTitle: "Plan \(clock(slot, input.calendar)) today", action: .planBlocks([slot]),
            weight: 0.85, confidence: 0.9
        )
    }

    static func weekendPlan(_ input: LifeRecInput) -> LifeRecommendation? {
        let free = past(input).filter { $0.type == .weekend || $0.type == .holiday }
        let lost = free.filter { $0.verdict == .unplannedLost }
        guard lost.count >= 2, !input.unplannedWeekend.isEmpty else { return nil }
        let planned = free.filter(\.planned)
        let plannedDid = planned.filter { $0.ownMinutes >= WeekMeasures.activeMinutes }.count
        let unplanned = free.filter { !$0.planned }
        let unplannedDid = unplanned.filter { $0.ownMinutes >= WeekMeasures.activeMinutes }.count
        var evidence = "\(lost.count) of your last \(free.count) days off went unplanned with little own work (\(dayList(lost.map(\.day), input.calendar)))."
        if !planned.isEmpty {
            evidence += " Planned days off: \(plannedDid) of \(planned.count) had own work; unplanned: \(unplannedDid) of \(unplanned.count)."
        }
        let hour = String(format: "%02d:00", input.freeDayHour)
        let times = input.unplannedWeekend.compactMap { input.calendar.date(bySettingHour: input.freeDayHour, minute: 0, second: 0, of: $0) }
        let names = input.unplannedWeekend.map { short(weekday: $0, input.calendar) }.joined(separator: " + ")
        return LifeRecommendation(
            id: LifeRecKind.weekendPlan.rawValue, kind: .weekendPlan, title: "Plan your weekend",
            evidence: evidence, impact: "Decide it now: a time on the calendar is the plan.",
            actionTitle: "Plan \(names) at \(hour)", action: .planBlocks(times),
            weight: min(1, 0.5 + Double(lost.count) / Double(max(1, free.count))), confidence: min(1, Double(free.count) / 4)
        )
    }

    static func leaveTarget(_ input: LifeRecInput) -> LifeRecommendation? {
        guard input.targets[.leave] == nil else { return nil }
        let leave = past(input).filter { $0.type == .leave }
        guard leave.count >= 2 else { return nil }
        let avg = leave.map(\.ownMinutes).reduce(0, +) / Double(leave.count)
        let proposed = min(300, max(input.goalMinutes + 30, roundTo(avg * 1.5, 30)))
        guard proposed > input.goalMinutes else { return nil }
        return LifeRecommendation(
            id: LifeRecKind.leaveTarget.rawValue, kind: .leaveTarget, title: "Leave days: aim higher",
            evidence: "Your \(leave.count) leave days averaged \(FFFormatLite.duration(avg)) of own work with no office load. They are judged by the workday goal (\(DayTargets.label(input.goalMinutes))).",
            impact: "A leave day has the most free hours you get.",
            actionTitle: "Set leave to \(DayTargets.label(proposed))", action: .setTarget(.leave, proposed),
            weight: 0.7, confidence: min(1, Double(leave.count) / 3)
        )
    }

    /// A day type whose target you rarely meet: a target you never hit stops steering you.
    static func targetMiss(_ input: LifeRecInput) -> LifeRecommendation? {
        let days = past(input)
        var best: LifeRecommendation?
        for type in [DayType.workday, .weekend, .leave, .holiday] {
            let of = days.filter { $0.type == type && $0.targetMinutes > 0 }
            guard of.count >= 4 else { continue }
            let target = of.last?.targetMinutes ?? 0
            let met = of.filter { $0.ownMinutes >= Double($0.targetMinutes) }.count
            let median = CoachPatterns.median(of.map(\.ownMinutes))
            guard Double(met) / Double(of.count) < 0.3, median < Double(target) * 0.6 else { continue }
            let proposed = max(30, roundTo(max(median * 1.3, Double(target) * 0.5), 15))
            guard proposed < target else { continue }
            let label = type.count(of.count)
            let rec = LifeRecommendation(
                id: "\(LifeRecKind.targetMiss.rawValue).\(type.rawValue)", kind: .targetMiss,
                title: "\(type.title)s: a target you can hit",
                evidence: "You met \(DayTargets.label(target)) on \(met) of \(label); a typical one had \(FFFormatLite.duration(median)) of own work.",
                impact: "Meet a smaller target often, then raise it (about \(DayTargets.label(proposed))).",
                actionTitle: type == .workday ? "Change it in Goals" : "Set \(type.title.lowercased()) to \(DayTargets.label(proposed))",
                action: type == .workday ? .openGoals : .setTarget(type, proposed),
                weight: 0.6, confidence: min(1, Double(of.count) / 8)
            )
            if best.map({ rec.score > $0.score }) ?? true { best = rec }
        }
        return best
    }

    /// Coach v7: blocks you run over are followed by long gaps.
    static func landOnTime(_ input: LifeRecInput) -> LifeRecommendation? {
        let c = input.cycle
        guard c.blocks >= 8, Double(c.stretchedBlocks) / Double(c.blocks) >= 0.4, let natural = input.naturalLength,
              natural != input.regularMinutes else { return nil }
        let rate = Int((Double(c.stretchedBlocks) / Double(c.blocks) * 100).rounded())
        var evidence = "\(rate)% of your blocks ran 5+ min over."
        if c.stretchedGaps.count >= 3, c.onTimeGaps.count >= 3 {
            evidence += " The next block came \(Int(CoachPatterns.median(c.stretchedGaps).rounded())) min later, against \(Int(CoachPatterns.median(c.onTimeGaps).rounded())) after one that ended on time."
        }
        return LifeRecommendation(
            id: LifeRecKind.landOnTime.rawValue, kind: .landOnTime, title: "Land on time",
            evidence: evidence, impact: "A length you finish lands the block and makes the next start easy.",
            actionTitle: "Try \(natural)-min blocks", action: .blockLength(natural),
            weight: 0.65, confidence: min(1, Double(c.blocks) / 20)
        )
    }

    /// Breaks that run long; an honest length puts the return cue where you actually are.
    static func breakLanding(_ input: LifeRecInput) -> LifeRecommendation? {
        guard let b = input.breaks, b.count >= 5, b.actual >= b.suggested * 1.5, b.actual - b.suggested >= 5 else { return nil }
        let proposed = Int(min(20, max(5, roundTo(b.actual * 0.75, 5))))
        guard Double(proposed) > b.suggested else { return nil }
        return LifeRecommendation(
            id: LifeRecKind.breakLanding.rawValue, kind: .breakLanding, title: "Breaks you come back from",
            evidence: "Your breaks run \(Int(b.actual.rounded())) min against \(Int(b.suggested.rounded())) planned (\(b.count) breaks).",
            impact: "Plan the break you take, and I cue the return when it ends.",
            actionTitle: "Make breaks \(proposed) min", action: .breakLength(proposed),
            weight: 0.5, confidence: min(1, Double(b.count) / 10)
        )
    }

    static func windowsFit(_ input: LifeRecInput) -> LifeRecommendation? {
        guard let fit = input.windowFit else { return nil }
        return LifeRecommendation(
            id: LifeRecKind.windowsFit.rawValue, kind: .windowsFit, title: "Watch the hours you work",
            evidence: "You start around \(fit.observed). Your set windows caught \(fit.covered) of \(fit.starts) starts.",
            impact: "Prompts land when you can act on them.",
            actionTitle: "Use these hours", action: .useObservedWindows,
            weight: 0.55, confidence: min(1, Double(fit.starts) / 20)
        )
    }

    static func appPull(_ input: LifeRecInput) -> LifeRecommendation? {
        guard let a = input.appPull, a.minutes >= 30 else { return nil }
        return LifeRecommendation(
            id: "\(LifeRecKind.appPull.rawValue).\(a.key).\(a.projectID.uuidString)", kind: .appPull,
            title: "\(a.name) in \(a.projectName) blocks",
            evidence: "\(FFFormatLite.duration(a.minutes)) of \(a.name) inside \(a.projectName) blocks on \(a.days) day\(a.days == 1 ? "" : "s").",
            impact: "Counted as a pull there, the coach nudges you back.",
            actionTitle: "A pull in \(a.projectName)", action: .appRole(key: a.key, name: a.name, projectID: a.projectID, role: .pull),
            weight: 0.45, confidence: min(1, a.minutes / 60)
        )
    }

    static func derailerHour(_ input: LifeRecInput) -> LifeRecommendation? {
        guard let d = input.derailer, d.minutes >= 120 else { return nil }
        let band = "\(String(format: "%02d", d.fromHour)):00–\(String(format: "%02d", d.toHour % 24)):00"
        let tomorrow = input.calendar.date(byAdding: .day, value: 1, to: input.calendar.startOfDay(for: input.now))
            .flatMap { input.calendar.date(bySettingHour: d.fromHour, minute: 0, second: 0, of: $0) }
        let action: LifeAction = d.isYourRule
            ? (tomorrow.map { .planBlocks([$0]) } ?? .markPull(key: d.key, name: d.name))
            : .markPull(key: d.key, name: d.name)
        return LifeRecommendation(
            id: "\(LifeRecKind.derailerHour.rawValue).\(d.key)", kind: .derailerHour, title: "\(d.name) around \(band)",
            evidence: "\(FFFormatLite.duration(d.minutes)) of \(d.name) in 2 weeks, most of it \(band).",
            impact: d.isYourRule ? "Put a block in that hour before it fills itself." : "Counted as a distraction, the coach speaks up at that hour.",
            actionTitle: d.isYourRule ? "Plan a \(String(format: "%02d", d.fromHour)):00 block" : "Count it as a distraction",
            action: action, weight: 0.5, confidence: min(1, d.minutes / 240)
        )
    }

    // MARK: Helpers

    /// The next weekend's days: Saturday and Sunday, or just Sunday on a Sunday. Today counts until 18:00.
    static func comingWeekend(now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        for offset in 0...6 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today), DayType.isWeekend(day, calendar: calendar) else { continue }
            if offset == 0 && calendar.component(.hour, from: now) >= 18 { continue }
            let isSaturday = calendar.component(.weekday, from: day) == 7
            return isSaturday ? [day, calendar.date(byAdding: .day, value: 1, to: day) ?? day] : [day]
        }
        return []
    }

    static func roundTo(_ value: Double, _ step: Int) -> Int {
        Int((value / Double(step)).rounded()) * step
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    static func short(weekday date: Date, _ calendar: Calendar) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendar.component(.weekday, from: date) - 1]
    }

    /// "18 Oct, 24 Oct and 25 Oct" (at most four).
    static func dayList(_ days: [Date], _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"
        let names = days.suffix(4).map { f.string(from: $0) }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }
}

// MARK: - Follow-up

/// What happened to a recommendation (shown in "Is the coach helping?").
struct LifeRecRecord: Codable, Equatable, Sendable {
    var id: String
    var kindRaw: String
    var title: String
    var firstShownAt: Date?
    var appliedAt: Date?
    var dismissedAt: Date?
    /// The measure over the 4 weeks before you applied it.
    var baseline: Double?
    /// Picked in a weekly review.
    var pickedAt: Date?

    var kind: LifeRecKind? {
        LifeRecKind(rawValue: kindRaw.split(separator: ".").first.map(String.init) ?? kindRaw)
    }
}

enum LifeRecOutcome: Equatable, Sendable {
    case tooEarly
    case worked(String)
    case didnt(String)
    /// Applied, with no measure to judge it by (windows, app roles).
    case applied
    case notTried

    var symbol: String {
        switch self {
        case .worked: "checkmark.circle.fill"
        case .didnt: "xmark.circle"
        case .tooEarly: "hourglass"
        case .applied: "checkmark.circle"
        case .notTried: "circle.dashed"
        }
    }

    var title: String {
        switch self {
        case .worked: "worked"
        case .didnt: "didn't help yet"
        case .tooEarly: "too early to tell"
        case .applied: "applied"
        case .notTried: "not tried"
        }
    }
}

enum LifeRecMetric {
    /// The measure a recommendation is judged by, over `entries` and `cycle`; nil without enough data.
    static func value(kind: LifeRecKind, id: String, entries: [DayEntry], cycle: CoachCycleStats?) -> Double? {
        let past = entries.filter { $0.verdict != .open }
        switch kind {
        case .weekendPlan:
            let free = past.filter { $0.type == .weekend || $0.type == .holiday }
            guard free.count >= 2 else { return nil }
            return Double(free.filter { $0.ownMinutes >= WeekMeasures.activeMinutes }.count) / Double(free.count)
        case .leaveTarget:
            let leave = past.filter { $0.type == .leave }
            guard !leave.isEmpty else { return nil }
            return leave.map(\.ownMinutes).reduce(0, +) / Double(leave.count)
        case .targetMiss:
            let type = DayType(rawValue: String(id.split(separator: ".").last ?? "")) ?? .workday
            let of = past.filter { $0.type == type && $0.targetMinutes > 0 }
            guard of.count >= 2 else { return nil }
            return Double(of.filter { $0.ownMinutes >= Double($0.targetMinutes) }.count) / Double(of.count)
        case .neverMissTwice:
            let pairs = zip(past, past.dropFirst()).filter { LifeRecommendations.isMiss($0.0) }
            guard pairs.count >= 2 else { return nil }
            return Double(pairs.filter { LifeRecommendations.isMiss($0.1) }.count) / Double(pairs.count)
        case .landOnTime:
            guard let cycle, cycle.blocks >= WeekMeasures.minBlocksForRates else { return nil }
            return Double(cycle.stretchedBlocks) / Double(cycle.blocks)
        case .breakLanding:
            guard let cycle, cycle.gaps.count >= 3 else { return nil }
            return cycle.medianGap
        case .windowsFit, .appPull, .derailerHour:
            return nil
        }
    }

    static let followUpAfter: TimeInterval = 7 * 86_400

    static func outcome(_ record: LifeRecRecord, current: Double?, now: Date) -> LifeRecOutcome {
        guard let applied = record.appliedAt else {
            return record.firstShownAt.map { now.timeIntervalSince($0) >= followUpAfter } == true ? .notTried : .tooEarly
        }
        guard let kind = record.kind, kind.isMeasured else { return .applied }
        guard now.timeIntervalSince(applied) >= followUpAfter, let before = record.baseline, let after = current else { return .tooEarly }
        let text = "\(format(before, kind)) → \(format(after, kind))"
        let change = after - before
        let threshold = kind.metricIsRate ? 0.1 : max(5, abs(before) * 0.1)
        if abs(change) < threshold { return .didnt(text) }
        return (change > 0) == kind.higherIsBetter ? .worked(text) : .didnt(text)
    }

    static func format(_ value: Double, _ kind: LifeRecKind) -> String {
        kind.metricIsRate ? "\(Int((value * 100).rounded()))%" : FFFormatLite.duration(value)
    }
}

/// Records in defaults (small, per Mac, like the coach's other answers; the store is not touched).
struct LifeRecStore {
    static let key = "focusflow.life.recommendations"
    static let keep = 60

    let defaults: UserDefaults

    func load() -> [String: LifeRecRecord] {
        guard let data = defaults.data(forKey: Self.key),
              let list = try? JSONDecoder().decode([LifeRecRecord].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func save(_ records: [String: LifeRecRecord]) {
        let list = records.values.sorted { ($0.firstShownAt ?? .distantPast) > ($1.firstShownAt ?? .distantPast) }.prefix(Self.keep)
        if let data = try? JSONEncoder().encode(Array(list)) { defaults.set(data, forKey: Self.key) }
    }

    /// The first time each one is shown (an applied one shown again after 21 days starts over).
    func markShown(_ recs: [LifeRecommendation], now: Date) {
        var records = load()
        var changed = false
        for rec in recs {
            let existing = records[rec.id]
            let restart = existing?.appliedAt.map { now.timeIntervalSince($0) > 21 * 86_400 } ?? false
            guard existing?.firstShownAt == nil || restart else { continue }
            var record = existing ?? LifeRecRecord(id: rec.id, kindRaw: rec.kind.rawValue, title: rec.title)
            record.firstShownAt = now
            record.appliedAt = nil
            record.baseline = nil
            record.title = rec.title
            records[rec.id] = record
            changed = true
        }
        if changed { save(records) }
    }

    func markApplied(_ rec: LifeRecommendation, baseline: Double?, picked: Bool = false, now: Date) {
        var records = load()
        var record = records[rec.id] ?? LifeRecRecord(id: rec.id, kindRaw: rec.kind.rawValue, title: rec.title, firstShownAt: now)
        record.appliedAt = now
        record.baseline = baseline
        record.dismissedAt = nil
        if picked { record.pickedAt = now }
        records[rec.id] = record
        save(records)
    }

    func dismiss(_ rec: LifeRecommendation, now: Date) {
        var records = load()
        var record = records[rec.id] ?? LifeRecRecord(id: rec.id, kindRaw: rec.kind.rawValue, title: rec.title, firstShownAt: now)
        record.dismissedAt = now
        records[rec.id] = record
        save(records)
    }
}
