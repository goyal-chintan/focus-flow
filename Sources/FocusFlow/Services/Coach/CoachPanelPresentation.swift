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
    /// Quiet footer line, e.g. "⌃⌥Space starts 5 min anytime".
    let footerHint: String?
    /// Keep-going panel: the step typed during the starter block.
    let step: String?

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
        step: String? = nil
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
    }

    /// Whether the panel has a primary button at all.
    var hasPrimary: Bool { kind != .notice && !message.primaryTitle.isEmpty }

    /// Auto-hide delay: notices are brief, everything else waits 20 s.
    var autoHideSeconds: Double { kind == .notice ? 3.5 : 20 }

    /// Label of the secondary menu ("Not now ▾"; the system draws the chevron).
    var menuTitle: String {
        switch kind {
        case .pseudoProductivity: "Not this"
        case .startNudge, .inSessionDrift, .weeklyPriorities, .rescue, .notice: "Not now"
        case .keepGoing: "I'm done · it counts"
        case .momentum: "Keep it short"
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
        }
    }

    /// A single secondary action renders as a plain button instead of a menu.
    var singleSecondary: CoachPanelSecondaryAction? {
        secondaryActions.count == 1 ? secondaryActions[0] : nil
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
        }
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

    var id: String { rawValue }
}

/// The AppKit host for the panel. `TimerViewModel` owns the content; the host only shows,
/// positions and hides the window.
@MainActor
protocol CoachPanelHosting: AnyObject {
    func showPanel(_ presentation: CoachPanelPresentation)
    func hidePanel()
}
