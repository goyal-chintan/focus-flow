import SwiftUI
import SwiftData

/// Idle popover, top: today's plan (Coach v3 §3.1). Either the next planned start with
/// Start now / Push / Skip, or (v4 §3.3) "start small, now": one click starts the coach's
/// suggested size, and one-click start times for later sit below. Below it,
/// "Today's line": one quote per day for the chosen coach style.
struct PopoverPlanCard: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PlannedBlock.startAt) private var plans: [PlannedBlock]

    @State private var slots: [CoachPlanSlot] = []
    @State private var ladder: CoachBlockSizeLadder.Recommendation?
    @State private var lineOffset = 0
    @State private var hoveredSlot: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 10) {
                planSection(now: now)
                if let line = todaysLine(now: now) {
                    lineView(line)
                }
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
            .task(id: Calendar.current.component(.hour, from: now)) {
                slots = timerVM.dailyPlanSuggestions(now: now)
            }
            .task(id: timerVM.completedFocusSessions) {
                ladder = timerVM.startLadderRecommendation(now: now)
            }
        }
        .animation(reduceMotion ? nil : FFMotion.section, value: nextPlan(now: Date())?.id)
    }

    // MARK: Plan

    private func nextPlan(now: Date) -> PlannedBlock? {
        plans.first { $0.status == .planned && $0.startAt > now.addingTimeInterval(-CoachPlannedCue.lateStart) }
    }

    private func plannedToday(now: Date) -> [PlannedBlock] {
        plans.filter { Calendar.current.isDate($0.day, inSameDayAs: now) }
    }

    @ViewBuilder
    private func planSection(now: Date) -> some View {
        if let plan = nextPlan(now: now) {
            plannedRow(plan, now: now)
        } else if let done = plannedToday(now: now).last(where: { $0.status == .started }) {
            statusRow(icon: "checkmark.circle.fill", tint: .green, title: "Plan kept · \(TimerViewModel.clockLabel(done.startAt))", subtitle: "Showing up is the habit. Again tomorrow.")
        } else if timerVM.todayFocusTime >= (timerVM.settings?.dailyFocusGoal ?? 7200) {
            statusRow(icon: "flag.checkered", tint: .green, title: "Today's goal is done", subtitle: "Rest is part of the system.")
        } else {
            chooser
        }
    }

    private func plannedRow(_ plan: PlannedBlock, now: Date) -> some View {
        let isDue = plan.startAt <= now
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isDue ? "alarm.fill" : "alarm")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDue ? Color.orange : LiquidDesignTokens.Spectral.primaryContainer)
                    .symbolEffect(.bounce, value: isDue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Planned \(TimerViewModel.clockLabel(plan.startAt)) · \(plan.minutes)m")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(isDue ? "It's time. Start small if you must." : "Starts \(relative(plan.startAt, now: now))\(plan.title.map { " · \($0)" } ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
                .tint(LiquidDesignTokens.Spectral.primaryContainer)

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
                .fixedSize()
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var chooser: some View {
        let suggested = ladder?.minutes ?? CoachBlockSizeLadder.defaultMinutes
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LiquidDesignTokens.Spectral.primaryContainer)
                    .accessibilityHidden(true)
                Text(timerVM.completedFocusSessions == 0 ? "Start small, now" : "Next block, small is fine")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            // One button: the coach's size. (The Duration picker below already offers every size.)
            HStack(alignment: .center, spacing: 10) {
                Button { timerVM.startNextBlock(minutes: suggested) } label: {
                    Label("Start \(suggested) min", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(minHeight: 24)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
                .help("Start \(suggested) minutes now (the coach's suggestion)")
                if let ladder {
                    Text(ladder.caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !slots.isEmpty {
                Text("Or plan it for later")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                HStack(spacing: 6) {
                    ForEach(slots) { slot in
                        slotButton(slot)
                    }
                }
            }
        }
    }

    private func slotButton(_ slot: CoachPlanSlot) -> some View {
        Button {
            timerVM.commitDailyPlan(slot)
        } label: {
            HStack(spacing: 4) {
                Text(slot.label())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(slot.caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hoveredSlot == slot.start
                          ? LiquidDesignTokens.Spectral.primaryContainer.opacity(0.18)
                          : Color.primary.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredSlot = $0 ? slot.start : (hoveredSlot == slot.start ? nil : hoveredSlot) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredSlot)
        .help("Plan a block at \(slot.label()). The coach shows up on screen then.")
        .accessibilityLabel("Plan at \(slot.label()), \(slot.caption)")
    }

    private func statusRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Today's line

    private func todaysLine(now: Date) -> CoachQuote? {
        CoachQuoteLibrary.dailyLine(style: timerVM.settings?.coachStyle ?? .challenger, on: now, offset: lineOffset)
    }

    private func lineView(_ quote: CoachQuote) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { lineOffset += 1 }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: CoachPanelPalette(style: timerVM.settings?.coachStyle ?? .challenger).gradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 2.5)
                VStack(alignment: .leading, spacing: 2) {
                    let text = quote.resolvedText(starterMinutes: timerVM.settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
                    Text(quote.isHouseLine ? text : "“\(text)”")
                        .font(.system(size: 12, weight: quote.isHouseLine ? .semibold : .regular))
                        .italic(!quote.isHouseLine)
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if !quote.isHouseLine {
                        Text("— \(quote.author)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .id(quote.id)
            .transition(.opacity)
        }
        .buttonStyle(.plain)
        .help(quote.isHouseLine ? "Today's line. Click for another." : "\(quote.attribution). Click for another.")
        .accessibilityLabel("Today's line: \(quote.formatted). Activate for another.")
    }

    private func relative(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "in \(hours)h" : "in \(hours)h \(rest)m"
    }
}
