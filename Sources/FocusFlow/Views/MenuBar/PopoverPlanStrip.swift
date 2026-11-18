import SwiftUI
import SwiftData

/// Idle popover, under the pace ring (`PopoverGoalHero`): a planned block, because it is a start
/// path. Due: "It's time" with Start now and Change. Coming: one line with Change. Nothing planned:
/// nothing at all.
struct PopoverPlanStrip: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PlannedBlock.startAt) private var plans: [PlannedBlock]

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .animation(reduceMotion ? nil : FFMotion.section, value: nextPlan(now: Date())?.id)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let plan = nextPlan(now: now) {
            Group {
                if plan.startAt <= now {
                    dueRow(plan)
                } else {
                    upcomingRow(plan, now: now)
                }
            }
        }
    }

    private func nextPlan(now: Date) -> PlannedBlock? {
        plans.first { $0.status == .planned && $0.startAt > now.addingTimeInterval(-CoachPlannedCue.lateStart) }
    }

    private func dueRow(_ plan: PlannedBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("It's time")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(FFPalette.atRisk)
                Text("Planned \(TimerViewModel.clockLabel(plan.startAt)) · \(plan.minutes)m\(plan.title.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Button {
                    timerVM.startPlannedBlockNow(id: plan.id)
                } label: {
                    Label("Start now", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(minHeight: 22)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
                .accessibilityLabel("Start the planned block now")
                changeMenu(plan)
                Spacer(minLength: 0)
            }
        }
    }

    private func upcomingRow(_ plan: PlannedBlock, now: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "alarm")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Spectral.primaryContainer)
                .accessibilityHidden(true)
            Text("Planned \(TimerViewModel.clockLabel(plan.startAt)) · \(plan.minutes)m · \(relative(plan.startAt, now: now))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 4)
            changeMenu(plan)
        }
        .frame(minHeight: 24)
    }

    private func changeMenu(_ plan: PlannedBlock) -> some View {
        Menu {
            Button("Push 15 min") { timerVM.pushPlannedBlock(id: plan.id, minutes: 15) }
            Button("Push 1 hour") { timerVM.pushPlannedBlock(id: plan.id, minutes: 60) }
            Divider()
            Button("Skip today", role: .destructive) { timerVM.skipPlannedBlock(id: plan.id) }
        } label: {
            Text("Change")
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(minHeight: 30)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Change the planned block")
    }

    private func relative(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "in \(hours)h" : "in \(hours)h \(rest)m"
    }
}
