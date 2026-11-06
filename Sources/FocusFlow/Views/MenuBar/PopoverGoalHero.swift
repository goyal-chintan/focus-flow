import SwiftUI

/// Idle popover, top (restored 6 Nov 2026): the pace ring with time to go, then a due or upcoming
/// plan. The coach's hook, the lever's reasoning and the other-projects line stay out: the coach
/// speaks in its panel, and "Working on" below holds the next step.
struct PopoverGoalHero: View {
    @Environment(TimerViewModel.self) private var timerVM

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let _ = (timerVM.todayFocusTime, timerVM.dayTargetsRevision)
        let goal = timerVM.dailyGoal(now: now)
        let done = timerVM.goalProgressSeconds(now: now)
        let tier = timerVM.goalPacing(now: now).tier
        let met = goal.seconds > 0 && done >= goal.seconds
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 4) {
                    PaceRing(done: done, target: goal.seconds, tier: tier, size: 66, lineWidth: 6)
                    Text(goal.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: 84)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(PopoverGoalHero.eyebrow(goal.scope))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(met ? "Target reached" : "\(FFFormat.duration(goal.seconds - done)) to go")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(met ? FFPalette.goal : .primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if met || tier != .unknown {
                        HStack(spacing: 6) {
                            PaceDot(tier: tier, met: met, size: 7)
                            Text(PopoverGoalHero.paceLine(tier, met: met))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            PopoverPlanStrip()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.md, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.md, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("popover.goalHero")
    }

    /// "YOUR #1 TODAY", "OWN WORK TODAY", "FOCUS TODAY".
    static func eyebrow(_ scope: GoalScope) -> String {
        switch scope {
        case .project: "YOUR #1 TODAY"
        case .ownWork: "OWN WORK TODAY"
        case .allFocus: "FOCUS TODAY"
        }
    }

    static func paceLine(_ tier: CoachGoalPacing.Tier, met: Bool) -> String {
        if met { return "Goal met" }
        switch tier {
        case .goalMet: return "Goal met"
        case .onTrack: return "On pace"
        case .nudge: return "Behind pace"
        case .atRisk: return "At risk today"
        case .unknown: return ""
        }
    }
}
