import SwiftUI
import SwiftData

/// Builds `CoachInsights.Summary` from the store and the coach's live model.
private struct CoachInsightsData {
    let summary: CoachInsights.Summary
    let nextPlan: PlannedBlock?
    let todayPlans: [PlannedBlock]

    @MainActor
    init(now: Date, sessions: [FocusSession], plans: [PlannedBlock], attempts: [InterventionAttempt], timerVM: TimerViewModel) {
        let calendar = Calendar.current
        let lookback = calendar.date(byAdding: .day, value: -(CoachInsights.lookbackDays + 1), to: calendar.startOfDay(for: now)) ?? now
        let sessionInputs = sessions
            .filter { $0.type == .focus && $0.startedAt >= lookback }
            .map { CoachInsights.SessionInput(start: $0.startedAt, seconds: $0.actualDuration, outcome: $0.outcome) }
        let planInputs = plans
            .filter { $0.day >= lookback }
            .map { CoachInsights.PlanInput(day: $0.day, startAt: $0.startAt, status: $0.status, pushes: $0.pushes) }
        let promptInputs = attempts
            .filter { $0.deliveredAt >= lookback && $0.kind != .quickPrompt }
            .map {
                CoachInsights.PromptInput(
                    deliveredAt: $0.deliveredAt,
                    outcome: $0.outcome,
                    reward: $0.reward,
                    isPlanned: $0.contextKey.map(CoachPlannedCue.isPlannedContextKey) ?? false
                )
            }
        summary = CoachInsights.summary(
            now: now,
            goalMinutes: Int((timerVM.settings?.dailyFocusGoal ?? 7200) / 60),
            sessions: sessionInputs,
            plans: planInputs,
            prompts: promptInputs,
            model: timerVM.availabilityModel,
            starterMinutes: CoachStarterBlock.clampedMinutes(timerVM.settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        )
        nextPlan = plans.first { $0.status == .planned && $0.startAt > now.addingTimeInterval(-CoachPlannedCue.lateStart) }
        todayPlans = plans.filter { calendar.isDate($0.day, inSameDayAs: now) }
    }
}

// MARK: - Today: "Your coach"

/// Today → "Your coach": today's plan, the never-miss-twice chain, learned windows left today
/// and up to three pieces of advice from the user's data, each with its source.
struct TodayCoachSection: View {
    let now: Date
    let sessions: [FocusSession]

    @Environment(TimerViewModel.self) private var timerVM
    @Query(sort: \PlannedBlock.startAt) private var plans: [PlannedBlock]
    @Query(sort: \InterventionAttempt.deliveredAt) private var attempts: [InterventionAttempt]
    @State private var slots: [CoachPlanSlot] = []

    var body: some View {
        let data = CoachInsightsData(now: now, sessions: sessions, plans: plans, attempts: attempts, timerVM: timerVM)
        FFSection("Your coach", subtitle: modelStatus(data.summary)) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                HStack(alignment: .top, spacing: FFSpace.l) {
                    planBlock(data)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    chainBlock(data.summary.chain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)

                if !data.summary.advice.isEmpty {
                    adviceGrid(data.summary.advice)
                }
            }
        }
        .task(id: Calendar.current.component(.hour, from: now)) {
            slots = timerVM.dailyPlanSuggestions(now: now)
        }
    }

    private func modelStatus(_ summary: CoachInsights.Summary) -> String {
        if summary.isLearned { return "Learned from your \(summary.learnedFromStarts) focus starts. Updates after every block." }
        if summary.learnedFromStarts > 0 { return "Learning your rhythm: \(summary.learnedFromStarts) of 8 starts needed for personal windows." }
        return "Start a few blocks and the coach learns when you work best."
    }

    @ViewBuilder
    private func planBlock(_ data: CoachInsightsData) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            Text("TODAY'S PLAN").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            if let plan = data.nextPlan {
                HStack(spacing: FFSpace.s) {
                    Image(systemName: "alarm.fill").foregroundStyle(FFPalette.accent).accessibilityHidden(true)
                    Text("\(TimerViewModel.clockLabel(plan.startAt)) · \(plan.minutes)m").ffNumber(.title3)
                }
                Text(plan.pushes > 0 ? "Pushed \(plan.pushes)× · the coach shows up on screen at that time" : "The coach shows up on screen at that time.")
                    .ffText(.caption)
                HStack(spacing: FFSpace.s) {
                    Button("Start now") { timerVM.startPlannedBlockNow(id: plan.id) }
                        .buttonStyle(.borderedProminent)
                    Button("Skip today") { timerVM.skipPlannedBlock(id: plan.id) }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            } else if let kept = data.todayPlans.last(where: { $0.status == .started }) {
                Label("Kept · \(TimerViewModel.clockLabel(kept.startAt))", systemImage: "checkmark.circle.fill")
                    .ffText(.headline)
                    .foregroundStyle(FFPalette.goal)
                Text("You did what you said you'd do. That is the habit.").ffText(.caption)
            } else if slots.isEmpty {
                Text("No plan").ffText(.headline)
                Text("Nothing free left today. Plan tomorrow's time in the morning.").ffText(.caption)
            } else {
                Text("No time decided yet").ffText(.headline)
                HStack(spacing: FFSpace.s) {
                    ForEach(slots) { slot in
                        Button {
                            timerVM.commitDailyPlan(slot)
                        } label: {
                            VStack(spacing: 0) {
                                Text(slot.label()).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                Text(slot.caption).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .frame(minWidth: 64)
                        }
                        .buttonStyle(.bordered)
                        .help("Plan today's block at \(slot.label())")
                    }
                }
                Text("One click. People who decide when are far likelier to start.").ffText(.caption)
            }
        }
    }

    private func chainBlock(_ chain: [CoachChainDay]) -> some View {
        let lastTwoMissed = chain.suffix(3).dropLast().allSatisfy { $0.mark == .missed }
        return VStack(alignment: .leading, spacing: FFSpace.s) {
            Text("NEVER MISS TWICE · 14 DAYS").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(chain) { day in
                    chainDot(day)
                }
            }
            Text(chainCaption(chain, lastTwoMissed: lastTwoMissed)).ffText(.caption)
        }
    }

    private func chainDot(_ day: CoachChainDay) -> some View {
        let fill: Color = switch day.mark {
        case .goal: FFPalette.goal
        case .partial: FFPalette.accent
        case .missed: FFPalette.track
        case .open: .clear
        }
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(day.mark == .open ? FFPalette.accent : FFPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: day.mark == .open ? [2, 2] : []))
            )
            .frame(width: 16, height: 16)
            .help("\(day.day.formatted(.dateTime.weekday(.abbreviated).day())): \(day.minutes)m")
            .accessibilityLabel("\(day.day.formatted(.dateTime.weekday(.wide).day())), \(day.minutes) minutes")
    }

    private func chainCaption(_ chain: [CoachChainDay], lastTwoMissed: Bool) -> String {
        let shown = chain.filter { $0.minutes > 0 }.count
        let yesterdayMissed = chain.dropLast().last?.mark == .missed
        let todayStarted = (chain.last?.minutes ?? 0) > 0
        if todayStarted { return "\(shown) of 14 days with a block. Today counts." }
        if yesterdayMissed { return "Yesterday was a miss. Today decides the habit: any block counts." }
        return "\(shown) of 14 days with a block. Green: goal met. Blue: showed up."
    }

    private func adviceGrid(_ advice: [CoachAdvice]) -> some View {
        HStack(alignment: .top, spacing: FFSpace.m) {
            ForEach(advice) { item in
                CoachAdviceCard(advice: item)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One advice card: symbol, title, a sentence from the user's data, and its source.
struct CoachAdviceCard: View {
    let advice: CoachAdvice
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            HStack(spacing: FFSpace.s) {
                Image(systemName: advice.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FFPalette.accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(FFPalette.accent.opacity(0.14)))
                    .accessibilityHidden(true)
                Text(advice.title).ffText(.headline)
            }
            Text(advice.body)
                .ffText(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Label(advice.citation, systemImage: "book.closed")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .help(advice.reference)
        }
        .padding(FFSpace.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: FFRadius.control + 2, style: .continuous)
                .fill(hovering ? FFPalette.rowHover : FFPalette.track.opacity(0.5))
        )
        .scaleEffect(hovering && !reduceMotion ? 1.01 : 1)
        .animation(FFAnimation.gated(FFAnimation.hover, reduceMotion: reduceMotion), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Insights: "What the coach learned"

/// Insights → "What the coach learned": when a start is likely (the coach's own posterior),
/// whether plans are kept, and whether prompts lead to starts.
struct CoachLearnedSection: View {
    let now: Date
    @Environment(TimerViewModel.self) private var timerVM
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query(sort: \PlannedBlock.startAt) private var plans: [PlannedBlock]
    @Query(sort: \InterventionAttempt.deliveredAt) private var attempts: [InterventionAttempt]
    @State private var hovered: Int?

    var body: some View {
        let data = CoachInsightsData(now: now, sessions: sessions, plans: plans, attempts: attempts, timerVM: timerVM)
        let summary = data.summary
        FFSection("What the coach learned", subtitle: "From your own starts: a Beta posterior per hour of the week, updated after every block.") {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                HStack(alignment: .top, spacing: FFSpace.l) {
                    FFStat(
                        label: "Plans kept · 14 days",
                        value: summary.plansMade == 0 ? "—" : "\(summary.plansKept) of \(summary.plansMade)",
                        caption: summary.plansMade == 0 ? "Plan a time from the menu bar" : "Started within the plan's window"
                    )
                    Divider()
                    FFStat(
                        label: "Start rate with a plan",
                        value: summary.startRatePlannedDays.map(CoachInsights.percent) ?? "—",
                        caption: summary.startRateUnplannedDays.map { "Without a plan: \(CoachInsights.percent($0))" } ?? "Needs 3+ days of each"
                    )
                    Divider()
                    FFStat(
                        label: "Prompts → starts",
                        value: summary.promptsSeen == 0 ? "—" : "\(summary.promptsLedToStart) of \(summary.promptsSeen)",
                        caption: "Prompts you saw, last 14 days"
                    )
                    Divider()
                    FFStat(
                        label: "Best hour today",
                        value: summary.bestHourThisWeekday.map { TimerViewModel.clockLabel($0.start) } ?? "—",
                        caption: summary.bestHourThisWeekday.map { String(format: "%.1f× your average hour", $0.lift) } ?? "Learning (needs 8 starts)"
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                if summary.isLearned {
                    heatmap
                } else {
                    FFEmptyState(
                        systemImage: "brain.head.profile",
                        message: "Still learning your rhythm",
                        detail: "After 8 focus starts the coach maps when you are most likely to begin and times its prompts and plan suggestions to it."
                    )
                }
            }
        }
    }

    /// 7 × 24 grid of the posterior start probability, Monday first.
    private var heatmap: some View {
        let model = timerVM.availabilityModel
        let calendar = Calendar.current
        let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let cells: [(index: Int, date: Date, p: Double)] = (0..<7).flatMap { day in
            (0..<24).compactMap { hour -> (Int, Date, Double)? in
                guard let date = calendar.date(byAdding: .hour, value: day * 24 + hour, to: calendar.startOfDay(for: monday)) else { return nil }
                return (day * 24 + hour, date, model.p(date))
            }
        }
        let peak = max(cells.map(\.p).max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text("").frame(width: 30)
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: 2) {
                    Text(FFFormat.weekdayShort[day]).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        let cell = cells[day * 24 + hour]
                        let good = model.isGoodWindow(cell.date)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(FFPalette.accent.opacity(0.08 + 0.85 * cell.p / peak))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(good ? FFPalette.goal.opacity(0.9) : .clear, lineWidth: 1)
                            )
                            .frame(height: 14)
                            .scaleEffect(hovered == cell.index ? 1.25 : 1)
                            .zIndex(hovered == cell.index ? 1 : 0)
                            .onHover { hovered = $0 ? cell.index : (hovered == cell.index ? nil : hovered) }
                            .help(String(format: "%@ %02d:00 · %.1f× your average hour%@", FFFormat.weekdayShort[day], hour, cell.p / max(model.meanRate, 0.0001), good ? " · learned window" : ""))
                    }
                }
            }
            HStack(spacing: FFSpace.m) {
                FFLegendItem(color: FFPalette.accent, label: "Likelier to start")
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(FFPalette.goal, lineWidth: 1).frame(width: 10, height: 10)
                    Text("Learned window (plan suggestions and prompts use these)").ffText(.caption)
                }
            }
            .padding(.top, 4)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heatmap of when you are most likely to start a focus block")
    }
}
