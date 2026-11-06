import Foundation

// Coach v3 start engine (docs/plans/2026-10-19-coach-v3-start-engine-design.md §3.1–3.2).
// Implementation intentions: the user decides *when* once a day, and the coach shows up on
// screen at that time. Everything here is pure and unit-tested; `TimerViewModel` wires it up.

// MARK: - Suggested start times

/// One suggested start time for today's block.
struct CoachPlanSlot: Equatable, Sendable, Identifiable {
    enum Reason: Equatable, Sendable {
        /// A learned good window. `lift` is how much likelier a start is than in the average hour.
        case bestWindow(lift: Double?)
        /// The next free half hour.
        case soon
        /// A fallback evening time.
        case evening
        /// One of the user's declared own-work windows.
        case ownWindow
        /// A fallback morning time.
        case morning
    }

    let start: Date
    let reason: Reason
    var id: Date { start }

    func label(calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: start)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Short reason under the chip: "Best window", "Next free", "Evening".
    var caption: String {
        switch reason {
        case .bestWindow(let lift):
            if let lift, lift >= 1.5 { return String(format: "%.1f× likelier", lift) }
            return "Best window"
        case .soon: return "Next free"
        case .evening: return "Evening"
        case .ownWindow: return "Your window"
        case .morning: return "Morning"
        }
    }
}

enum CoachDailyPlanner {
    static let granularityMinutes = 30
    static let minimumLead: TimeInterval = 10 * 60
    /// A suggestion needs this much free calendar time after it.
    static let requiredFreeMinutes = 25
    /// Two suggestions are at least this far apart.
    static let minimumSpacing: TimeInterval = 90 * 60
    /// How far ahead suggestions look (late-night users plan past midnight).
    static let horizon: TimeInterval = 10 * 60 * 60
    static let eveningHours = [21, 22]

    /// Up to `maxCount` start times, in time order: the strongest learned windows that are free,
    /// the next free half hour, then evening fallbacks. Never in quiet hours or a busy event.
    static func suggestions(
        now: Date,
        model: CoachAvailabilityModel,
        busy: [DateInterval],
        quietStartMinute: Int,
        quietEndMinute: Int,
        maxCount: Int = 3,
        calendar: Calendar = .current
    ) -> [CoachPlanSlot] {
        let candidates = candidateStarts(now: now, busy: busy, quietStartMinute: quietStartMinute, quietEndMinute: quietEndMinute, calendar: calendar)
        guard !candidates.isEmpty else { return [] }
        var picked: [CoachPlanSlot] = []

        func farFromPicked(_ date: Date, spacing: TimeInterval = minimumSpacing) -> Bool {
            picked.allSatisfy { abs($0.start.timeIntervalSince(date)) >= spacing }
        }

        // 1. Learned windows, strongest first (on the hour reads better than :30).
        if model.mode != .noData {
            let ranked = candidates
                .filter { model.isGoodWindow($0) }
                .sorted { lhs, rhs in
                    let l = model.p(lhs), r = model.p(rhs)
                    if l != r { return l > r }
                    let lOnHour = calendar.component(.minute, from: lhs) == 0
                    let rOnHour = calendar.component(.minute, from: rhs) == 0
                    if lOnHour != rOnHour { return lOnHour }
                    return lhs < rhs
                }
            for date in ranked where picked.count < max(1, maxCount - 1) && farFromPicked(date) {
                let lift = model.meanRate > 0 ? model.p(date) / model.meanRate : nil
                picked.append(CoachPlanSlot(start: date, reason: .bestWindow(lift: lift)))
            }
        }

        // 2. The next free half hour, so "now-ish" is always one click.
        if picked.count < maxCount, let soon = candidates.first, picked.allSatisfy({ abs($0.start.timeIntervalSince(soon)) >= 60 * 60 }) {
            picked.append(CoachPlanSlot(start: soon, reason: .soon))
        }

        // 3. Evening fallbacks.
        for hour in eveningHours where picked.count < maxCount {
            guard let date = candidates.first(where: {
                calendar.component(.hour, from: $0) == hour && calendar.component(.minute, from: $0) == 0
            }), farFromPicked(date, spacing: 60 * 60) else { continue }
            picked.append(CoachPlanSlot(start: date, reason: .evening))
        }

        return Array(picked.sorted { $0.start < $1.start }.prefix(maxCount))
    }

    /// Half-hour starts from `now + 10 min`, outside quiet hours and with 25 free minutes.
    static func candidateStarts(
        now: Date,
        busy: [DateInterval],
        quietStartMinute: Int,
        quietEndMinute: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        let earliest = now.addingTimeInterval(minimumLead)
        guard var cursor = roundUp(earliest, toMinutes: granularityMinutes, calendar: calendar) else { return [] }
        let end = now.addingTimeInterval(horizon)
        var result: [Date] = []
        while cursor <= end {
            if CoachGuardrails.isQuietHours(cursor, start: quietStartMinute, end: quietEndMinute, calendar: calendar) {
                // Stop at the first quiet hour: nothing is suggested across the night.
                break
            }
            let block = DateInterval(start: cursor, duration: TimeInterval(requiredFreeMinutes * 60))
            if !busy.contains(where: { $0.intersects(block) && $0.end > block.start && $0.start < block.end }) {
                result.append(cursor)
            }
            cursor = cursor.addingTimeInterval(TimeInterval(granularityMinutes * 60))
        }
        return result
    }

    static func roundUp(_ date: Date, toMinutes step: Int, calendar: Calendar = .current) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let hourStart = calendar.date(from: DateComponents(
            year: parts.year, month: parts.month, day: parts.day, hour: parts.hour
        )) else { return nil }
        let minute = parts.minute ?? 0
        let hasRemainder = (parts.second ?? 0) > 0 || minute % step != 0
        let rounded = hasRemainder ? (minute / step + 1) * step : minute
        return hourStart.addingTimeInterval(TimeInterval(rounded * 60))
    }

    /// Block length for a plan: the pacing suggestion (25–50 min).
    static func blockMinutes(pacing: CoachGoalPacing) -> Int {
        pacing.suggestedBlockMinutes
    }
}

// MARK: - The cue at the planned time

enum CoachPlannedCue {
    /// `InterventionAttempt.contextKey` prefix for planned cues and the plan card: requested
    /// by the user, so they never use up the daily cap.
    static let contextPrefix = "plan:"
    static let inviteContextKey = "plan:invite"

    /// A block started this long before the planned time still fulfils the plan.
    static let earlyStart: TimeInterval = 30 * 60
    /// After this the plan is missed.
    static let lateStart: TimeInterval = 90 * 60
    /// A busy calendar at the planned time delays the cue at most this long (to the meeting's end).
    static let calendarDeferLimit: TimeInterval = 60 * 60
    /// ✕ / Esc / "Push 15 min" more than this marks the plan missed.
    static let maxPushes = 3
    static let pushMinutes = 15

    static func contextKey(blockID: UUID) -> String { contextPrefix + blockID.uuidString }

    static func isPlannedContextKey(_ key: String) -> Bool { key.hasPrefix(contextPrefix) }

    /// A cue for a block the user planned (not the start card, which the coach chose to show).
    static func isRequestedCueKey(_ key: String) -> Bool { isPlannedContextKey(key) && key != inviteContextKey }

    enum Step: Equatable, Sendable {
        case notYet
        case cue
        /// Busy in the calendar: cue when the meeting ends (a natural breakpoint).
        case waitForCalendar
        case expire
    }

    static func step(startAt: Date, now: Date, calendarBusy: Bool) -> Step {
        if now < startAt { return .notYet }
        let late = now.timeIntervalSince(startAt)
        if late >= lateStart { return .expire }
        if calendarBusy { return late < calendarDeferLimit ? .waitForCalendar : .expire }
        return .cue
    }

    /// A focus block that started at `sessionStart` fulfils a plan for `startAt`.
    static func fulfills(startAt: Date, sessionStart: Date) -> Bool {
        sessionStart >= startAt.addingTimeInterval(-earlyStart) && sessionStart <= startAt.addingTimeInterval(lateStart)
    }

    /// New start after a push: `minutes` from now (or from the plan, if it is still ahead).
    static func pushed(startAt: Date, now: Date, minutes: Int) -> Date {
        max(startAt, now).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Whether one more push is allowed; past the limit the plan is missed.
    static func canPush(pushes: Int) -> Bool { pushes < maxPushes }
}

// MARK: - The daily plan card

enum CoachDailyPlanInvite {
    /// A closed card means "later", so it may come back once. Coach v6 §3.2 stops the one that came
    /// right after midnight (`beforeDayStart`), which used a cap slot on 1, 2 and 5 Nov 2026.
    static let maxPerDay = 2
    static let retryAfter: TimeInterval = 2 * 60 * 60
    /// The user must have touched the keyboard or mouse within this (a breakpoint, not a void).
    static let maxIdleSeconds: TimeInterval = 60

    struct Input: Sendable {
        var now: Date
        var hasPlanToday: Bool
        var goalMet: Bool
        var sessionActive: Bool
        var quietHours: Bool
        var calendarBusy: Bool
        var screenShare: Bool
        var released: Bool
        var userIdleSeconds: TimeInterval
        var panelShowing: Bool
        var log: Log
        /// No suggestion left today (late at night): nothing to offer.
        var hasSuggestions: Bool
        /// The day's interrupting prompts are used up (the card counts, coach audit 2026-10-30).
        var capReached: Bool = false
        /// Own-work windows are declared and none is open: not a moment to ask.
        var outsideOwnWindow: Bool = false
        /// Before quiet hours end (00:00 up to 07:00 by default): the night before, not the day's
        /// first breakpoint. The card fired at 00:00 and 00:15 on three days.
        var beforeDayStart: Bool = false
    }

    /// Per-day state, stored in defaults.
    struct Log: Codable, Equatable, Sendable {
        var day: Date
        var shown: Int = 0
        var lastShownAt: Date?
        /// "Not today".
        var declined: Bool = false

        static func fresh(for now: Date, calendar: Calendar = .current) -> Log {
            Log(day: calendar.startOfDay(for: now))
        }

        func current(for now: Date, calendar: Calendar = .current) -> Log {
            calendar.isDate(day, inSameDayAs: now) ? self : .fresh(for: now, calendar: calendar)
        }
    }

    static func shouldInvite(_ input: Input, calendar: Calendar = .current) -> Bool {
        let log = input.log.current(for: input.now, calendar: calendar)
        guard !input.hasPlanToday, !input.goalMet, !input.sessionActive, !input.quietHours,
              !input.calendarBusy, !input.screenShare, !input.released, !input.panelShowing,
              input.hasSuggestions, !input.capReached, !input.outsideOwnWindow, !input.beforeDayStart, !log.declined, log.shown < maxPerDay,
              input.userIdleSeconds <= maxIdleSeconds else { return false }
        if let last = log.lastShownAt, input.now.timeIntervalSince(last) < retryAfter { return false }
        return true
    }
}

struct CoachDailyPlanInviteStore {
    static let key = "focusflow.coachDailyPlanInvite.v1"
    let defaults: UserDefaults

    func load(now: Date) -> CoachDailyPlanInvite.Log {
        guard let data = defaults.data(forKey: Self.key),
              let log = try? JSONDecoder().decode(CoachDailyPlanInvite.Log.self, from: data) else {
            return .fresh(for: now)
        }
        return log.current(for: now)
    }

    func save(_ log: CoachDailyPlanInvite.Log) {
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: Self.key) }
    }
}

// MARK: - Plan tomorrow (coach audit 2026-10-30)

/// The evening check-in: "When are tomorrow's 2 blocks?" Deciding the night before is an
/// implementation intention (Gollwitzer & Sheeran, 2006, d ≈ 0.65); each time picked becomes a
/// `PlannedBlock`, so the planned-start cue shows up at that time tomorrow.
enum CoachPlanTomorrow {
    /// A user-requested check-in (on in Settings): never uses up the daily cap of start prompts.
    static let contextKey = CoachPlannedCue.contextPrefix + "tomorrow"
    static let blocks = 2
    /// Not before 19:00, and not before today's last own-work window has ended.
    static let earliestMinute = 19 * 60
    /// Times at least this far apart.
    static let spacing: TimeInterval = 90 * 60
    static let maxSlots = 4
    static let fallbackMinutes = [7 * 60 + 30, 21 * 60]

    struct Input: Sendable {
        var now: Date
        var enabled: Bool
        var plannedTomorrow: Int
        var askedToday: Bool
        var sessionActive: Bool
        var quietHours: Bool
        var screenShare: Bool
        var panelShowing: Bool
        var userIdleSeconds: TimeInterval
        /// End of today's last declared window, minutes after midnight.
        var lastWindowEndMinute: Int?
    }

    static func shouldAsk(_ input: Input, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: input.now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return input.enabled
            && minute >= max(earliestMinute, input.lastWindowEndMinute ?? 0)
            && !input.askedToday
            && input.plannedTomorrow < blocks
            && !input.sessionActive && !input.quietHours && !input.screenShare && !input.panelShowing
            && input.userIdleSeconds <= CoachDailyPlanInvite.maxIdleSeconds
    }

    /// Start times for tomorrow, in time order: your declared windows' starts first, then the
    /// learned windows' best hours, then 07:30 and 21:00. Never in quiet hours, never within
    /// 90 minutes of each other or of a block already planned.
    static func slots(
        now: Date,
        windows: [CoachOwnWorkWindow],
        model: CoachAvailabilityModel,
        quietStartMinute: Int,
        quietEndMinute: Int,
        planned: [Date] = [],
        calendar: Calendar = .current
    ) -> [CoachPlanSlot] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        var picked: [CoachPlanSlot] = []
        func at(_ minute: Int) -> Date? { calendar.date(byAdding: .minute, value: minute, to: tomorrow) }
        func add(_ date: Date?, _ reason: CoachPlanSlot.Reason) {
            guard let date, picked.count < maxSlots,
                  !CoachGuardrails.isQuietHours(date, start: quietStartMinute, end: quietEndMinute, calendar: calendar),
                  (picked.map(\.start) + planned).allSatisfy({ abs($0.timeIntervalSince(date)) >= spacing }) else { return }
            picked.append(CoachPlanSlot(start: date, reason: reason))
        }
        for window in windows { add(at(window.startMinute), .ownWindow) }
        if windows.isEmpty, model.mode != .noData {
            let hours = (0..<24).compactMap { at($0 * 60) }.filter { model.isGoodWindow($0) }
            for date in hours.sorted(by: { model.p($0) > model.p($1) }) {
                let lift = model.meanRate > 0 ? model.p(date) / model.meanRate : nil
                add(date, .bestWindow(lift: lift))
            }
        }
        if picked.count < blocks {
            add(at(fallbackMinutes[0]), .morning)
            add(at(fallbackMinutes[1]), .evening)
        }
        return picked.sorted { $0.start < $1.start }
    }
}

/// The day the plan-tomorrow check-in last asked (defaults).
struct CoachPlanTomorrowStore {
    static let key = "focusflow.coachPlanTomorrow.v1"
    let defaults: UserDefaults

    func askedToday(now: Date, calendar: Calendar = .current) -> Bool {
        let stamp = defaults.double(forKey: Self.key)
        guard stamp > 0 else { return false }
        return calendar.isDate(Date(timeIntervalSince1970: stamp), inSameDayAs: now)
    }

    func markAsked(now: Date) {
        defaults.set(now.timeIntervalSince1970, forKey: Self.key)
    }
}
