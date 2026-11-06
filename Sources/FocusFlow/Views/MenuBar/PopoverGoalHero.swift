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
                PaceRing(done: done, target: goal.seconds, tier: tier)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(PaceRing.word(tier, met: met)) · \(goal.label)".uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(PaceRing.color(tier, met: met))
                        .lineLimit(1)
                    Text(met ? "Target reached" : "\(FFFormat.duration(goal.seconds - done)) to go")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(met ? FFPalette.goal : .primary)
                        .monospacedDigit()
                        .lineLimit(1)
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
}
