import Foundation

// Coach v4: start first (docs/plans/2026-10-28-coach-v4-start-first-design.md).
// The coach's job is one thing: get a block started. Everything here is pure and unit-tested;
// `TimerViewModel` feeds it the store and the system idle time.

// MARK: - Presence (§3.2)

/// Is anyone at the Mac? Idle start prompts only show to someone who can see them: 7 of 8
/// start panels after v3 appeared at an empty desk and hid unseen.
enum CoachPresence {
    /// Keyboard or mouse input this recently means the user is at the desk.
    static let presentWithin: TimeInterval = 90
    /// Away at least this long, then back: an arrival (a natural breakpoint).
    static let arrivalAwayThreshold: TimeInterval = 10 * 60

    static func isPresent(systemIdleSeconds: TimeInterval) -> Bool {
        systemIdleSeconds < presentWithin
    }

    /// Fed the system idle time on every coach tick; reports the tick the user comes back.
    struct ArrivalDetector: Sendable, Equatable {
        /// Longest idle reading since the user was last present.
        private(set) var awayPeak: TimeInterval = 0

        /// True on the first present reading after being away ≥ 10 minutes.
        mutating func observe(systemIdleSeconds idle: TimeInterval) -> Bool {
            guard CoachPresence.isPresent(systemIdleSeconds: idle) else {
                awayPeak = max(awayPeak, idle)
                return false
            }
            let arrived = awayPeak >= CoachPresence.arrivalAwayThreshold
            awayPeak = 0
            return arrived
        }
    }
}

// MARK: - Block size ladder (§3.3)

/// Picks the block size the coach asks for: 5, 15 or 25 minutes. Proximal goals beat distal
/// ones (Bandura & Schunk, 1981), so the coach never asks for the day's goal, only the next
/// block, and it shrinks the ask when asks don't land.
///
/// A pure fold over recent history, so nothing extra is stored and it can't drift out of sync.
enum CoachBlockSizeLadder {
    static let sizes = [5, 15, 25]
    static let defaultMinutes = 15
    /// Seen asks in a row with no start before the ask shrinks one size.
    static let declinesToShrink = 2
    /// Completed blocks in a row at (or above) the current size before the ask grows one size.
    static let completionsToGrow = 3
    static let lookbackDays = 21

    struct Event: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            /// A prompt the user saw and did not act on. `reason` is the "Not now" reason, if any.
            case declined(reason: FocusCoachSkipReason?)
            /// A block started from (or within 10 minutes of) a prompt.
            case startedFromPrompt(minutes: Int)
            /// A focus block ended (prompted or not).
            case blockEnded(minutes: Int, completed: Bool)
        }

        let at: Date
        let kind: Kind
    }

    struct Recommendation: Sendable, Equatable {
        enum Why: Sendable, Equatable {
            /// No signal yet.
            case starting
            /// The size the user last started from a prompt.
            case lastStart
            /// The last asks didn't land.
            case shrunkAfterDeclines
            /// "It feels too big".
            case tooBig
            /// "I don't know the next step": spend the block finding it.
            case findNextStep
            /// Three finished blocks in a row: ready for a bigger ask.
            case grew
            /// v5: Learner B picked it from your own responses (overrides the rule).
            case learned(asks: Int)
        }

        let minutes: Int
        let why: Why

        /// The ask is "5 minutes to find the next step", not a work block.
        var findsNextStep: Bool { why == .findNextStep }

        /// The `.starting` reason, for logs and tooltips. On a start prompt it would be the fourth
        /// "start small" line (screen audit 2026-10-28), so `panelCaption` drops it.
        static let startingCaption = "Small starts count."

        /// The line under the size pills on a prompt: nil when there is no real reason to give.
        var panelCaption: String? { why == .starting ? nil : caption }

        /// One line under the size pills, e.g. "5m: the last two asks didn't land".
        var caption: String {
            switch why {
            case .starting: Self.startingCaption
            case .lastStart: "\(minutes)m is what you started last time."
            case .shrunkAfterDeclines: "\(minutes)m: the last asks didn't land, so smaller."
            case .tooBig: "\(minutes)m: you said it felt too big."
            case .findNextStep: "\(minutes)m to find the next step. That's the whole job."
            case .grew: "\(minutes)m: you finished your last three. Step up."
            case .learned(let asks): "\(minutes)m: what you actually start at this time, learned from \(asks) asks."
            }
        }
    }

    static func nearestSize(_ minutes: Int) -> Int {
        sizes.min { abs($0 - minutes) < abs($1 - minutes) } ?? defaultMinutes
    }

    static func recommend(events: [Event]) -> Recommendation {
        var index = sizes.firstIndex(of: defaultMinutes) ?? 1
        var why = Recommendation.Why.starting
        var declines = 0
        var completions = 0

        for event in events.sorted(by: { $0.at < $1.at }) {
            switch event.kind {
            case .declined(let reason):
                switch reason {
                case .taskTooBig?:
                    index = 0; why = .tooBig; declines = 0; completions = 0
                case .unclearNextStep?:
                    index = 0; why = .findNextStep; declines = 0; completions = 0
                case nil, .procrastinating?, .cantFocus?, .lowPriorityWork?:
                    declines += 1
                    completions = 0
                    if declines >= declinesToShrink {
                        declines = 0
                        if index > 0 { index -= 1; why = .shrunkAfterDeclines }
                    }
                default:
                    // Busy, tired, a meeting: a real reason, not a sign the ask was too big.
                    break
                }
            case .startedFromPrompt(let minutes):
                index = sizes.firstIndex(of: nearestSize(minutes)) ?? index
                why = .lastStart
                declines = 0
            case .blockEnded(let minutes, let completed):
                guard completed else { completions = 0; continue }
                if minutes >= sizes[index] - 1 {
                    completions += 1
                    if completions >= completionsToGrow {
                        completions = 0
                        if index < sizes.count - 1 { index += 1; why = .grew }
                    }
                }
            }
        }
        return Recommendation(minutes: sizes[index], why: why)
    }
}

// MARK: - "Not now, because…" (§3.4)

/// What the coach does with a reasoned decline. Mental contrasting with implementation
/// intentions: name the obstacle, then a concrete "if…then" (Wang, Wang & Gai, 2021).
enum CoachDeclineResponse {
    /// Reasons offered under "Not now ▾" on start prompts, in menu order.
    static let reasons: [FocusCoachSkipReason] = [.urgentTask, .justTired, .taskTooBig, .unclearNextStep]

    /// Menu label (the enum's own names read as a report, these read as an answer).
    static func label(_ reason: FocusCoachSkipReason) -> String {
        switch reason {
        case .urgentTask: "Busy with work"
        case .justTired: "Too tired"
        case .taskTooBig: "It feels too big"
        case .unclearNextStep: "I don't know the next step"
        default: reason.displayName
        }
    }

    /// Hour from which "too tired" means "done for tonight".
    static let tiredEveningHour = 20

    enum Action: Equatable, Sendable {
        /// Stay quiet until this time.
        case quietUntil(Date)
        /// Re-ask right away, smaller: the "then" of the if-then plan.
        case counterOffer(minutes: Int, findNextStep: Bool)
    }

    static func action(for reason: FocusCoachSkipReason, now: Date, calendar: Calendar = .current) -> Action {
        switch reason {
        case .taskTooBig:
            return .counterOffer(minutes: CoachBlockSizeLadder.sizes[0], findNextStep: false)
        case .unclearNextStep:
            return .counterOffer(minutes: CoachBlockSizeLadder.sizes[0], findNextStep: true)
        case .justTired where calendar.component(.hour, from: now) >= tiredEveningHour:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            return .quietUntil(tomorrow ?? now.addingTimeInterval(12 * 3600))
        default:
            return .quietUntil(now.addingTimeInterval(60 * 60))
        }
    }
}

// MARK: - Honest attribution (§3.1)

/// Which prompt gets the credit for a focus start. Before v4 only the prompt's own button
/// counted; the plan card's starts (made from the popover a minute later) all logged as 0.
enum CoachPromptAttribution {
    struct Candidate: Sendable, Equatable {
        let id: UUID
        let deliveredAt: Date
        let surface: CoachSurface?
        let outcome: FocusCoachOutcome?
        let reward: Double?
        let hasContext: Bool
    }

    /// The most recent prompt the user saw in the 10 minutes before `start` that is not yet
    /// credited. Badges are ambient and silent arms showed nothing, so neither gets credit.
    static func creditTarget(for start: Date, candidates: [Candidate], window: TimeInterval = 10 * 60) -> UUID? {
        candidates
            .filter { candidate in
                candidate.hasContext
                    && candidate.outcome != .unseen
                    && candidate.surface != .badge && candidate.surface != .silent
                    && (candidate.reward ?? 0) <= 0
                    && candidate.deliveredAt <= start
                    && start.timeIntervalSince(candidate.deliveredAt) <= window
            }
            .max { $0.deliveredAt < $1.deliveredAt }?
            .id
    }
}

extension CoachPromptAttribution {
    /// Plain name of a prompt for the journal and insights: "start card", "rescue (L2)", …
    static func label(contextKey: String?, surface: CoachSurface?) -> String {
        guard let key = contextKey else { return "prompt" }
        if key == CoachPlannedCue.inviteContextKey { return "start card" }
        if CoachPlannedCue.isPlannedContextKey(key) { return "planned cue" }
        if let level = CoachContextKey(rawValue: key)?.driftLevel { return "rescue (L\(level.rawValue))" }
        return surface == .badge ? "menu-bar badge" : "start nudge"
    }
}

// MARK: - Rescues respect the day job (§3.5)

enum CoachRescueWindowPolicy {
    /// On-screen rescues (panel, pause screen) run only in learned windows. Elsewhere the
    /// rescue stays on the menu-bar counter: 17 rescues at low/medium availability led to 0 starts.
    static func allowsOnScreen(tier: CoachAvailabilityModel.Tier, modelHasData: Bool) -> Bool {
        guard modelHasData else { return true }
        return tier == .high
    }
}
