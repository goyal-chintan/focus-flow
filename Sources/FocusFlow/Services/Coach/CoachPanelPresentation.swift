import Foundation

/// What the on-screen coach panel shows (companion redesign §5).
struct CoachPanelPresentation: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable, Equatable {
        case startNudge
        case pseudoProductivity
        case inSessionDrift
        case weeklyPriorities
        /// Rescue loop: the ladder ask at the current drift level.
        case rescue
        /// End of a starter block: "Keep going: 20m on {step}?"
        case keepGoing
        /// Five minutes into a rescue-started block: "You're in. Make it 25?"
        case momentum
        /// Short confirmation, no actions (e.g. "Starter block started · 5 min").
        case notice
        /// v3 §3.2: the user's planned start time has come. Stays until answered.
        case plannedStart
        /// v4 §3.3: the start card: "Start 5 · 15 · 25 now", with time chips for later.
        /// Stays until answered.
        case dailyPlan
        /// Coach audit 2026-10-30: the evening "When are tomorrow's 2 blocks?" check-in.
        /// Each time chip plans one block. Stays until answered.
        case planTomorrow
    }

    let id: UUID
    let kind: Kind
    let message: CoachComposedMessage
    /// What the primary button starts (start nudge and pseudo-productivity answers).
    let plan: CoachStartTarget?
    /// The `InterventionAttempt` this panel was logged as, for outcomes and rewards.
    let attemptID: UUID?
    /// Name of the frontmost context when the panel was raised (pseudo-productivity log).
    let contextName: String?
    let createdAt: Date
    /// Rescue loop: the drift level this panel was raised at.
    let level: DriftLevel?
    /// Rescue loop: what the primary button starts (normal block or starter block).
    let ask: CoachRescueAsk?
    /// Quiet footer line, e.g. `CoachStarterBlock.hotkeyHint`.
    let footerHint: String?
    /// Keep-going panel: the step typed during the starter block.
    let step: String?
    /// Planned-start cue: the `PlannedBlock` it is for.
    let plannedBlockID: UUID?
    /// Daily plan card: the suggested start times (one click each).
    let planSlots: [CoachPlanSlot]
    /// v4 §3.3: one-click block sizes (5 · 15 · 25). Empty: a single primary button.
    let sizeOptions: [Int]
    /// The size the ladder recommends (highlighted, Return starts it).
    let recommendedMinutes: Int?
    /// Why that size, e.g. "5m: you said it felt too big."
    let sizeCaption: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        message: CoachComposedMessage,
        plan: CoachStartTarget? = nil,
        attemptID: UUID? = nil,
        contextName: String? = nil,
        createdAt: Date = Date(),
        level: DriftLevel? = nil,
        ask: CoachRescueAsk? = nil,
        footerHint: String? = nil,
        step: String? = nil,
        plannedBlockID: UUID? = nil,
        planSlots: [CoachPlanSlot] = [],
        sizeOptions: [Int] = [],
        recommendedMinutes: Int? = nil,
        sizeCaption: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.plan = plan
        self.attemptID = attemptID
        self.contextName = contextName
        self.createdAt = createdAt
        self.level = level
        self.ask = ask
        self.footerHint = footerHint
        self.step = step
        self.plannedBlockID = plannedBlockID
        self.planSlots = planSlots
        self.sizeOptions = sizeOptions
        self.recommendedMinutes = recommendedMinutes
        // The default size has no reason worth a line; the hook already says "start small".
        self.sizeCaption = sizeCaption == CoachBlockSizeLadder.Recommendation.startingCaption ? nil : sizeCaption
    }

    /// Whether the panel has a primary button at all.
    /// Size pills replace the primary button (the recommended pill takes Return).
    var hasPrimary: Bool { kind != .notice && sizeOptions.isEmpty && !message.primaryTitle.isEmpty }

    /// Auto-hide delay. Nil means the panel stays until it is answered (v3 §3.2–3.3, R3):
    /// before v3 every panel hid after 20 s, and 4 of 5 live prompts vanished unseen.
    var autoHideSeconds: Double? {
        switch kind {
        case .notice: 3.5
        case .keepGoing, .momentum, .inSessionDrift: 20
        case .startNudge, .rescue, .pseudoProductivity, .weeklyPriorities: 180
        case .plannedStart, .dailyPlan, .planTomorrow: nil
        }
    }

    /// Label of the secondary menu ("Not now ▾"; the system draws the chevron). Its reasons
    /// section reads "Not now, because…" (shared vocabulary, screen audit 2026-10-28).
    var menuTitle: String {
        switch kind {
        case .startNudge, .pseudoProductivity, .inSessionDrift, .weeklyPriorities, .rescue, .notice: "Not now"
        case .keepGoing: "I'm done · it counts"
        case .momentum: "Keep it short"
        case .plannedStart: "Not yet"
        case .dailyPlan: "Not now"
        case .planTomorrow: "Not tonight"
        }
    }

    var secondaryActions: [CoachPanelSecondaryAction] {
        switch kind {
        case .startNudge, .rescue: [.snooze15, .snooze60, .doneForToday]
        case .pseudoProductivity: [.sideQuest, .planned]
        case .inSessionDrift: [.partOfWork, .snooze15, .endBlock]
        case .weeklyPriorities: [.snooze60, .skipWeek]
        case .keepGoing: [.finishStarter]
        case .momentum: [.keepShort]
        case .notice: []
        case .plannedStart: [.starterInstead, .push15, .push60, .skipToday]
        case .dailyPlan: [.planLater, .notToday]
        case .planTomorrow: [.notToday]
        }
    }

    /// v4 §3.4: "Not now, because…" on prompts that ask for a start. Each reason changes the
    /// next ask. Not on a counter-offer (it already answers a reason).
    var reasonActions: [CoachPanelSecondaryAction] {
        if case .counterOffer = message.trigger { return [] }
        switch kind {
        case .startNudge, .dailyPlan, .rescue: return CoachPanelSecondaryAction.reasons
        default: return []
        }
    }

    /// A single secondary action renders as a plain button instead of a menu.
    var singleSecondary: CoachPanelSecondaryAction? {
        secondaryActions.count == 1 && reasonActions.isEmpty ? secondaryActions[0] : nil
    }

    /// What Esc does once the panel has been clicked ("Not now").
    var escapeAction: CoachPanelSecondaryAction? {
        switch kind {
        case .startNudge, .rescue, .inSessionDrift: .snooze15
        case .pseudoProductivity: .planned
        case .weeklyPriorities: .snooze60
        case .keepGoing: .finishStarter
        case .momentum: .keepShort
        case .notice: nil
        case .plannedStart: .push15
        case .dailyPlan: .planLater
        case .planTomorrow: .notToday
        }
    }

    func title(for action: CoachPanelSecondaryAction) -> String {
        switch action {
        case .snooze15: kind == .inSessionDrift ? "Ask again in 15 min" : "15 minutes"
        case .snooze60: kind == .weeklyPriorities ? "Remind me later" : "1 hour"
        case .doneForToday: "Done for today"
        case .sideQuest: "Side quest: start \(plan?.name.map(CoachMessageComposer.shortName) ?? "it") instead"
        case .planned: "Planned, leave me"
        case .partOfWork: "It's part of the work"
        case .endBlock: "End block (time is saved)"
        case .skipWeek: "Skip this week"
        case .finishStarter: "I'm done · it counts"
        case .keepShort: "Keep it short"
        case .starterInstead: "Just \(starterMinutes) minutes instead"
        case .push15: "Push 15 min"
        case .push60: "Push 1 hour"
        case .skipToday: "Skip today"
        case .planLater: "Ask me in 2 hours"
        case .notToday: kind == .planTomorrow ? "Not tonight" : "Not today"
        case .reasonBusy, .reasonTired, .reasonTooBig, .reasonUnclear:
            action.declineReason.map(CoachDeclineResponse.label) ?? ""
        }
    }

    /// Starter length shown in "Just N minutes instead" (from the planned cue's copy).
    private var starterMinutes: Int {
        if case .plannedStart(let cue) = message.trigger { return cue.starterMinutes }
        return CoachStarterBlock.defaultMinutes
    }
}

enum CoachPanelSecondaryAction: String, CaseIterable, Sendable, Identifiable {
    case snooze15
    case snooze60
    case doneForToday
    case sideQuest
    case planned
    case partOfWork
    case endBlock
    case skipWeek
    /// Keep-going panel: decline; the starter still counts as a completed block.
    case finishStarter
    /// Momentum ramp: keep the block at its current length.
    case keepShort
    /// Planned cue: start a starter block instead of the full block (two-minute rule).
    case starterInstead
    /// Planned cue: move the plan 15 minutes / 1 hour.
    case push15
    case push60
    /// Planned cue: skip today's plan (respected, not counted as ignored).
    case skipToday
    /// Daily plan card: ask again in 2 hours.
    case planLater
    /// Daily plan card: no plan today.
    case notToday
    /// v4 §3.4: "Not now, because…"
    case reasonBusy
    case reasonTired
    case reasonTooBig
    case reasonUnclear

    var id: String { rawValue }

    static let reasons: [CoachPanelSecondaryAction] = [.reasonBusy, .reasonTired, .reasonTooBig, .reasonUnclear]

    var declineReason: FocusCoachSkipReason? {
        switch self {
        case .reasonBusy: .urgentTask
        case .reasonTired: .justTired
        case .reasonTooBig: .taskTooBig
        case .reasonUnclear: .unclearNextStep
        default: nil
        }
    }
}

/// The AppKit host for the panel. `TimerViewModel` owns the content; the host only shows,
/// positions and hides the window.
@MainActor
protocol CoachPanelHosting: AnyObject {
    func showPanel(_ presentation: CoachPanelPresentation)
    func hidePanel()
}
