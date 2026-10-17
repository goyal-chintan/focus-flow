import Foundation

// Rescue loop (docs/plans/2026-10-17-coach-rescue-loop-design.md §2–§3): the ask shrinks as
// drift deepens, a starter block needs no project, and escalation never depends on
// notifications. Everything here is pure and unit-tested; `TimerViewModel` wires it up.

// MARK: - Micro-commitment ladder

/// What a rescue asks for. The primary button title comes from here.
struct CoachRescueAsk: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        /// A normal block on the priority (L1: N from pacing, L2: 10 minutes).
        case normal
        /// A starter block: no project or priority needed (L3).
        case starter
    }

    let kind: Kind
    let minutes: Int
    let title: String
    /// Priority or project for a normal block.
    let target: CoachStartTarget?
}

enum CoachRescueLadder {
    static let lostMinutes = 10

    /// L1: "Start {N}m on {priority}", L2: "Just 10 minutes on {priority}",
    /// L3: "{starter} minutes. Plan the next step." (starter block). L0 asks nothing.
    static func ask(level: DriftLevel, target: CoachStartTarget, starterMinutes: Int) -> CoachRescueAsk? {
        let name = target.name.map(CoachMessageComposer.shortName).flatMap { $0.isEmpty ? nil : $0 }
        switch level {
        case .ok:
            return nil
        case .drifting:
            return CoachRescueAsk(kind: .normal, minutes: target.minutes, title: CoachMessageComposer.startTitle(target), target: target)
        case .lost:
            var tenMinutes = target
            tenMinutes.minutes = lostMinutes
            let title = name.map { "Just 10 minutes on \($0)" } ?? "Just 10 minutes"
            return CoachRescueAsk(kind: .normal, minutes: lostMinutes, title: title, target: tenMinutes)
        case .spiral:
            let minutes = CoachStarterBlock.clampedMinutes(starterMinutes)
            return CoachRescueAsk(kind: .starter, minutes: minutes, title: CoachStarterBlock.planTitle(minutes: minutes), target: nil)
        }
    }
}

// MARK: - Starter block

/// A short block that needs no project or priority. Starter sessions carry
/// `customLabel == "Starter"` and no project, so analytics read them as
/// `AnalyticsProjectKey.label("Starter")` without a model change. The typed next step is saved
/// as the session's `intentText`.
enum CoachStarterBlock {
    static let label = "Starter"
    static let allowedMinutes = [2, 5, 10]
    static let defaultMinutes = 5
    /// "Keep going" continues with a normal block of this length.
    static let keepGoingMinutes = 20
    /// A starter "kept going" when a ≥ 20-minute block starts within this gap after it.
    static let keepGoingGap: TimeInterval = 5 * 60
    static let keptGoingMinimumSeconds: TimeInterval = 20 * 60

    static func clampedMinutes(_ minutes: Int) -> Int {
        allowedMinutes.contains(minutes) ? minutes : (minutes < 2 ? 2 : min(10, max(2, minutes)))
    }

    static func planTitle(minutes: Int) -> String { "\(minutes) minutes. Plan the next step." }
    static func pauseScreenTitle(minutes: Int) -> String { "Start \(minutes) minutes" }
    static func hotkeyHint(minutes: Int) -> String { "⌃⌥Space starts \(minutes) min anytime" }
    static func startedNotice(minutes: Int) -> String { "Starter block started · \(minutes) min" }

    static func isStarter(customLabel: String?, hasProject: Bool) -> Bool {
        !hasProject && customLabel == label
    }

    /// "Keep going: 20m on {step}?"
    static func keepGoingHook(step: String?) -> String {
        if let step = step.map(trimmedStep), !step.isEmpty {
            return "Keep going: \(keepGoingMinutes)m on \(step)?"
        }
        return "Keep going: \(keepGoingMinutes) more minutes?"
    }

    static func trimmedStep(_ step: String) -> String {
        let line = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count > 40 else { return line }
        return String(line.prefix(39)) + "…"
    }
}

// MARK: - Momentum ramp

/// "You're in. Make it 25?" once, 5 minutes into a rescue-started block shorter than 25 minutes.
enum CoachMomentumRamp {
    static let offerAfter: TimeInterval = 5 * 60
    static let targetMinutes = 25
    static let hook = "You're in. Make it 25?"

    static func shouldOffer(isRescueStart: Bool, isStarter: Bool, elapsedSeconds: TimeInterval, totalSeconds: TimeInterval, alreadyOffered: Bool) -> Bool {
        guard isRescueStart, !isStarter, !alreadyOffered else { return false }
        return elapsedSeconds >= offerAfter && totalSeconds < TimeInterval(targetMinutes * 60)
    }

    /// Seconds to add so the block totals 25 minutes.
    static func extensionSeconds(totalSeconds: TimeInterval) -> TimeInterval {
        max(0, TimeInterval(targetMinutes * 60) - totalSeconds)
    }
}

// MARK: - Surfaces and cadence

/// Where a rescue was shown. Stored in the bandit context key (`surf:`).
enum CoachRescueSurface: String, CaseIterable, Sendable {
    case panel
    case pauseScreen
    /// Only the menu bar counter (the bandit's silent arm).
    case ambient

    /// The `CoachSurface` logged on the attempt. The pause screen is a full-screen strong
    /// window, so it is stored as `.strongWindow` (no model change needed).
    var coachSurface: CoachSurface {
        switch self {
        case .panel: .panel
        case .pauseScreen: .strongWindow
        case .ambient: .silent
        }
    }

    init(coachSurface: CoachSurface) {
        switch coachSurface {
        case .strongWindow: self = .pauseScreen
        case .silent, .badge, .notification: self = .ambient
        case .panel: self = .panel
        }
    }

    var label: String {
        switch self {
        case .panel: "Panel"
        case .pauseScreen: "Pause screen"
        case .ambient: "Menu bar only"
        }
    }
}

/// When the rescue loop makes a new decision: on a level rise, in a new window, or after
/// 20 minutes at the same level.
enum CoachRescueCadence {
    struct Decision: Equatable, Sendable {
        let level: DriftLevel
        let at: Date
        let windowStart: Date
    }

    static let repeatAfter: TimeInterval = 20 * 60

    static func shouldDecide(level: DriftLevel, windowStart: Date, last: Decision?, now: Date) -> Bool {
        guard level > .ok else { return false }
        guard let last, last.windowStart == windowStart else { return true }
        if level > last.level { return true }
        return now.timeIntervalSince(last.at) >= repeatAfter
    }

    /// Surfaces a level allows before guardrails: L1–L2 menu bar or panel; L3 adds the pause screen.
    static func candidateSurfaces(level: DriftLevel, panelEnabled: Bool, pauseScreenAllowed: Bool) -> [CoachSurface] {
        guard level > .ok else { return [.silent] }
        var surfaces: [CoachSurface] = [.silent]
        if panelEnabled { surfaces.append(.panel) }
        if level == .spiral && pauseScreenAllowed { surfaces.append(.strongWindow) }
        return surfaces
    }
}

// MARK: - Pause screen guardrails

/// One logged rescue, read back from an `InterventionAttempt` (contextKey `lvl:` / `surf:`).
struct CoachRescueRecord: Equatable, Sendable {
    let deliveredAt: Date
    let level: DriftLevel
    let surface: CoachRescueSurface
    let outcome: FocusCoachOutcome?
    let reward: Double?

    /// Started a block from it (reward ≥ 1 or outcome improved).
    var ledToStart: Bool { (reward ?? 0) >= 1 || outcome == .improved }
    /// Dismissed (✕/Esc) or ignored (auto-hid, expired). "Not now" snoozes are not ignores.
    var wasIgnored: Bool { outcome == .ignored || outcome == .dismissed }

    init(deliveredAt: Date, level: DriftLevel, surface: CoachRescueSurface, outcome: FocusCoachOutcome? = nil, reward: Double? = nil) {
        self.deliveredAt = deliveredAt
        self.level = level
        self.surface = surface
        self.outcome = outcome
        self.reward = reward
    }

    init?(contextKey: String?, deliveredAt: Date, outcome: FocusCoachOutcome?, reward: Double?) {
        guard let contextKey, let key = CoachContextKey(rawValue: contextKey),
              let level = key.driftLevel, let surface = key.rescueSurface else { return nil }
        self.init(deliveredAt: deliveredAt, level: level, surface: surface, outcome: outcome, reward: reward)
    }

    init?(attempt: InterventionAttempt) {
        self.init(contextKey: attempt.contextKey, deliveredAt: attempt.deliveredAt, outcome: attempt.outcome, reward: attempt.reward)
    }
}

enum CoachPauseScreenPolicy {
    static let maxPerWeek = 3
    static let escapeRateLimit = 0.8
    static let escapeLookback: TimeInterval = 14 * 24 * 3600
    /// Pause screens needed in the lookback before the escape rate can switch it off.
    static let minimumShowsForShutoff = 4
    /// The ✕ fades in after this long; Esc works at once.
    static let closeButtonDelay: TimeInterval = 8

    enum Verdict: String, Equatable, Sendable {
        case allowed
        case disabledInSettings
        case notSpiral
        case alreadyShownThisWindow
        case weeklyCap
        case escapeRateTooHigh
        case screenShare
        case calendarBusy
        case quietHours
        case released
        case snoozed
        case sessionActive
        case dailyCapReached
    }

    struct Input: Sendable {
        var enabled: Bool
        var level: DriftLevel
        var windowStart: Date
        var now: Date
        /// Rescues logged in (at least) the last 14 days.
        var records: [CoachRescueRecord]
        /// The shared hard limits (quiet hours, calendar, screen share, release, cap).
        var guardrails: CoachGuardrails.Input
    }

    static func verdict(_ input: Input) -> Verdict {
        guard input.enabled else { return .disabledInSettings }
        guard input.level == .spiral else { return .notSpiral }
        var hard = input.guardrails
        hard.ignorePanelSpacing = true
        switch CoachGuardrails().verdict(for: .strongWindow, input: hard) {
        case .allowed: break
        case .sessionActive: return .sessionActive
        case .released: return .released
        case .screenShare: return .screenShare
        case .calendarBusy: return .calendarBusy
        case .quietHours: return .quietHours
        case .snoozed: return .snoozed
        case .dailyCapReached: return .dailyCapReached
        case .panelTooSoon: break
        }
        let pauses = input.records.filter { $0.surface == .pauseScreen }
        if pauses.contains(where: { $0.deliveredAt >= input.windowStart && $0.deliveredAt <= input.now }) {
            return .alreadyShownThisWindow
        }
        let weekStart = input.now.addingTimeInterval(-7 * 24 * 3600)
        if pauses.filter({ $0.deliveredAt > weekStart }).count >= maxPerWeek { return .weeklyCap }
        if isAutoDisabled(records: input.records, now: input.now) { return .escapeRateTooHigh }
        return .allowed
    }

    /// Share of pause screens in the last 14 days that did not lead to a start. Nil below the minimum sample.
    static func escapeRate(records: [CoachRescueRecord], now: Date) -> Double? {
        let start = now.addingTimeInterval(-escapeLookback)
        let pauses = records.filter { $0.surface == .pauseScreen && $0.deliveredAt > start && $0.deliveredAt <= now }
        guard pauses.count >= minimumShowsForShutoff else { return nil }
        return Double(pauses.filter { !$0.ledToStart }.count) / Double(pauses.count)
    }

    /// Escape rate above 80% over 14 days switches the surface off. It comes back by itself once
    /// those shows age out of the 14-day window.
    static func isAutoDisabled(records: [CoachRescueRecord], now: Date) -> Bool {
        (escapeRate(records: records, now: now) ?? 0) > escapeRateLimit
    }
}

/// How the user left the pause screen.
enum CoachPauseScreenExit: String, Sendable {
    case startStarter
    case escape
    case close
    case realBreak
    case doneForToday
}
