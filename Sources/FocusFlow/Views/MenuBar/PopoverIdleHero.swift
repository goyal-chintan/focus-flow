import SwiftUI
import SwiftData

/// Idle popover, top (screen audit 2026-10-28): the same hero as the notch's idle view.
/// Own-work ring "50m of 2h", the coach's hook only when it prompted, then today's lever
/// ("TODAY'S LEVER" · action · "goal · reason"). A due planned block takes the lever's place.
struct PopoverIdleHero: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PlannedBlock.startAt) private var plans: [PlannedBlock]
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]

    /// First of `GoalDataBuilder.levers` (computed by the parent so the goal field offers the same one).
    let lever: DailyLever?

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .animation(reduceMotion ? nil : FFMotion.section, value: nextPlan(now: Date())?.id)
    }

    private func content(now: Date) -> some View {
        let done = timerVM.goalProgressSeconds(now: now)
        let target = timerVM.settings?.dailyFocusGoal ?? 7200
        let plan = nextPlan(now: now)
        let isDue = plan.map { $0.startAt <= now } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                PopoverGoalRing(
                    done: done,
                    target: target,
                    label: GoalDataBuilder.ownWorkConfigured(projects) ? "Own work" : "Focus today"
                )
                VStack(alignment: .leading, spacing: 3) {
                    if let hook = coachHook {
                        Text(hook)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)
                    }
                    if let plan, isDue {
                        dueColumn(plan)
                    } else {
                        leverColumn(goalMet: target > 0 && done >= target)
                    }
                }
                Spacer(minLength: 0)
            }
            if let plan, !isDue {
                upcomingRow(plan, now: now)
            } else if plan == nil, let kept = keptPlan(now: now) {
                statusLine(icon: "checkmark.circle.fill", tint: .green, text: "Plan kept · \(TimerViewModel.clockLabel(kept.startAt)). Again tomorrow.")
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
    }

    // MARK: Coach hook

    /// The coach's line, only while it is asking for a start (panel up, popover prompt, or pulse).
    private var coachHook: String? {
        if let panel = timerVM.coachPanel { return panel.message.hook }
        if let decision = timerVM.activeCoachPopoverDecision,
           let model = FocusCoachPresentationMapper.mapDecision(decision) {
            return model.title
        }
        return timerVM.coachMenuBarPulse ? "The coach has a start for you." : nil
    }

    // MARK: Lever

    private func leverColumn(goalMet: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            heroLabel(lever == nil ? "Next block" : "Today's lever", tint: .secondary)
            Text(lever?.action ?? fallbackAction(goalMet: goalMet))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(lever.map { "\($0.goalTitle) · \($0.reason)" } ?? (goalMet ? "Rest is part of the system." : "Small starts count."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fallbackAction(goalMet: Bool) -> String {
        if goalMet { return "Today's goal is done" }
        let project = timerVM.selectedProject
            ?? projects.filter { $0.priorityRank != nil }.min { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }
        return project.map { "Start on \($0.name)" } ?? "Start a small block"
    }

    // MARK: Planned block

    private func nextPlan(now: Date) -> PlannedBlock? {
        plans.first { $0.status == .planned && $0.startAt > now.addingTimeInterval(-CoachPlannedCue.lateStart) }
    }

    private func keptPlan(now: Date) -> PlannedBlock? {
        plans.last { Calendar.current.isDate($0.day, inSameDayAs: now) && $0.status == .started }
    }

    private func dueColumn(_ plan: PlannedBlock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            heroLabel("It's time", tint: .orange)
            Text("Planned \(TimerViewModel.clockLabel(plan.startAt)) · \(plan.minutes)m")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(plan.title ?? "Start small if you must.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
            }
            .padding(.top, 3)
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

    // MARK: Pieces

    private func heroLabel(_ text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(tint)
    }

    private func statusLine(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func relative(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "in \(hours)h" : "in \(hours)h \(rest)m"
    }
}

/// "50m of 2h" around a 64 pt ring: own work (once a project is marked Work) against the daily goal.
struct PopoverGoalRing: View {
    let done: TimeInterval
    let target: TimeInterval
    let label: String

    private var fraction: Double { target > 0 ? min(1, done / target) : 0 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(fraction >= 1 ? FFPalette.goal : FFPalette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(FFFormat.duration(done))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("of \(FFFormat.duration(target))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 64, height: 64)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(FFFormat.duration(done)) of \(FFFormat.duration(target))")
    }
}

/// "Plan for later": today's suggested start times (Coach v3 plan slots) in a plain menu link.
struct PopoverPlanLaterMenu: View {
    @Environment(TimerViewModel.self) private var timerVM
    @State private var slots: [CoachPlanSlot] = []

    var body: some View {
        ZStack {
            if slots.isEmpty {
                // Keeps the view on screen so `.task` runs and loads the slots.
                Color.clear.frame(width: 1, height: 1)
            } else {
                Menu {
                    ForEach(slots) { slot in
                        Button("\(slot.label()) · \(slot.caption)") { timerVM.commitDailyPlan(slot) }
                    }
                } label: {
                    Text("Plan for later")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(minHeight: 30)
                .foregroundStyle(.secondary)
                .help("Pick a start time today. The coach shows up on screen then.")
                .accessibilityLabel("Plan a block for later today")
            }
        }
        .task(id: Calendar.current.component(.hour, from: Date())) {
            slots = timerVM.dailyPlanSuggestions(now: Date())
        }
    }
}
