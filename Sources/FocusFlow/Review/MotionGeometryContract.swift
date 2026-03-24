import Foundation

enum MotionTransitionIntent: String {
    case disclosureFold
    case transientFeedback
}

struct GeometryBaseline: Hashable {
    let width: Double
    let height: Double?
}

enum MotionGeometryContract {
    /// Transition intent map for critical animated interactions.
    static let transitionIntents: [String: MotionTransitionIntent] = [
        "SessionComplete.coachReasonDisclosure": .disclosureFold,
        "SessionComplete.capturedReasonPill": .transientFeedback,
        "CoachIntervention.banner": .disclosureFold,
        "MenuBar.pauseReasonChipStrip": .disclosureFold,
        "MenuBar.projectSwitchReasonChipStrip": .disclosureFold,
        "MenuBar.startErrorBanner": .transientFeedback,
        "MenuBar.coachStripEntrance": .disclosureFold,
        "CalendarTab.reminderRemoval": .transientFeedback
    ]

    /// First-render geometry baselines for surfaces prone to jumpy size changes.
    static let geometryBaselines: [String: GeometryBaseline] = [
        "SessionComplete.breakPane": GeometryBaseline(width: 480, height: nil),
        "MenuBar.popoverShell": GeometryBaseline(width: 310, height: nil),
        "CoachIntervention.window": GeometryBaseline(width: 360, height: nil)
    ]
}
