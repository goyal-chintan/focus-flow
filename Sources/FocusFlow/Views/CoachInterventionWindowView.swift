import SwiftUI

/// Standalone rendering of the coach panel for previews and evidence captures.
///
/// Coach v2 retired the auto-opening "Focus Coach" window and its app activation: idle prompts
/// and the in-session drift check both use the floating `CoachPanelController` panel
/// (companion redesign §5). This view draws the same `CoachPanelView` from the view model's
/// current panel, or from the decision behind it.
struct CoachInterventionWindowView: View {
    @Environment(TimerViewModel.self) private var timerVM

    private var presentation: CoachPanelPresentation? {
        if let panel = timerVM.coachPanel { return panel }
        guard let decision = timerVM.activeCoachInterventionDecision else { return nil }
        let isInSession = timerVM.state != .idle
        let message = decision.composed ?? CoachMessageComposer.neutralFallback(isInSession: isInSession)
        return CoachPanelPresentation(kind: isInSession ? .inSessionDrift : .startNudge, message: message)
    }

    var body: some View {
        Group {
            if let presentation {
                CoachPanelView(
                    presentation: presentation,
                    chrome: .standalone,
                    errorText: timerVM.coachPanelError ?? timerVM.startError,
                    onPrimary: { timerVM.performCoachPanelPrimary() },
                    onSecondary: { timerVM.performCoachPanelSecondary($0) },
                    onClose: { timerVM.dismissCoachInterventionWindow() }
                )
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            }
        }
        .padding(12)
    }
}
