import SwiftUI
import SwiftData

/// Builds `CoachInsights.Summary` from the store and the coach's live model.
private struct CoachInsightsData {
    let summary: CoachInsights.Summary

    /// `samples` are the goal samples (own work once a project is marked Work), so the
    /// never-miss-twice chain and the "started that day" checks never count office time.
    @MainActor
    init(now: Date, samples: [FocusSample], plans: [PlannedBlock], attempts: [InterventionAttempt], timerVM: TimerViewModel) {
        let calendar = Calendar.current
        let lookback = calendar.date(byAdding: .day, value: -(CoachInsights.lookbackDays + 1), to: calendar.startOfDay(for: now)) ?? now
        let sessionInputs = samples
            .filter { $0.isFocus && $0.start >= lookback }
            .map { CoachInsights.SessionInput(start: $0.start, seconds: $0.activeSeconds, outcome: $0.outcome) }
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
                    // v4: the start card is a coach prompt; only cues for planned blocks are excluded.
                    isPlanned: $0.contextKey.map(CoachPlannedCue.isRequestedCueKey) ?? false,
                    label: CoachPromptAttribution.label(contextKey: $0.contextKey, surface: $0.surfaceRawValue.flatMap(CoachSurface.init(rawValue:))),
                    skipReason: $0.skipReason
                )
            }
        summary = CoachInsights.summary(
            now: now,
            goalMinutes: Int(timerVM.dailyGoal(now: now).seconds / 60),
            sessions: sessionInputs,
            plans: planInputs,
            prompts: promptInputs,
            model: timerVM.availabilityModel,
            starterMinutes: CoachStarterBlock.clampedMinutes(timerVM.settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        )
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

// MARK: - Settings → Coach: "How the coach is doing"

/// Is the coach getting you started? (moved from Insights to Settings → Coach, structural redesign
/// 2026-10-30: Insights answers your questions, this answers the coach's). Does a prompt lead to a
/// start (against the moments it stayed quiet), the next ask, what stops you, the research cards and
/// today's log. How the coach learns sits in a collapsed "How the coach decides".
struct CoachPerformanceView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.companionNowOverride) private var nowOverride
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]
    @Query(sort: \PlannedBlock.startAt) private var plans: [PlannedBlock]
    @Query(sort: \InterventionAttempt.deliveredAt) private var attempts: [InterventionAttempt]
    @State private var showLog = false
    @State private var showModel = false

    /// "A prompt counts when you start a block within 20 minutes · last 14 days".
    static var countingRule: String {
        "A prompt counts when you start a block within \(Int(CoachDecisionReward.startWindow / 60)) minutes · last \(CoachInsights.lookbackDays) days"
    }

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, projects: projects, now: nowOverride ?? Date())
        let now = snapshot.now
        let summary = CoachInsightsData(now: now, samples: snapshot.goalSamples, plans: plans, attempts: attempts, timerVM: timerVM).summary
        let learning = timerVM.coachLearningSummary(now: now)
        let ladder = timerVM.startLadderRecommendation(now: now)
        VStack(alignment: .leading, spacing: FFSpace.l) {
            Text(Self.countingRule).ffText(.caption)
            headline(summary, learning: learning, ladder: ladder)
            Divider()
            promptsAndReasons(summary)
            if !summary.advice.isEmpty {
                // Two per row: the Settings pane is narrower than the companion page.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: FFSpace.m, alignment: .top), GridItem(.flexible(), spacing: FFSpace.m, alignment: .top)], spacing: FFSpace.m) {
                    ForEach(summary.advice) { CoachAdviceCard(advice: $0) }
                }
            }
            logDisclosure(now: now)
            modelDisclosure(summary, learning: learning, snapshot: snapshot)
        }
        .padding(.vertical, FFSpace.xs)
    }

    // MARK: Headline

    private func headline(_ summary: CoachInsights.Summary, learning: TimerViewModel.CoachLearningSummary, ladder: CoachBlockSizeLadder.Recommendation) -> some View {
        HStack(alignment: .top, spacing: FFSpace.l) {
            FFStat(
                label: "Prompt → start",
                value: summary.promptsSeen == 0 ? "—" : CoachInsights.percent(Double(summary.promptsLedToStart) / Double(summary.promptsSeen)),
                caption: summary.promptsSeen == 0 ? "No prompts seen yet" : "\(summary.promptsLedToStart) of \(summary.promptsSeen) prompts you saw"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            if let lift = learning.lift {
                FFStat(
                    label: "Without a prompt",
                    value: CoachInsights.percent(lift.withoutPrompt),
                    caption: "With one: \(CoachInsights.percent(lift.withPrompt)) · \(String(format: "%+.0f", lift.lift * 100)) points (\(lift.decisions) moments)",
                    valueColor: nil
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FFStat(
                    label: "Without a prompt",
                    value: "Measuring",
                    caption: "\(learning.decisions) moments so far, \(learning.quietDecisions) of them quiet on purpose. Needs 20 to compare."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            FFStat(label: "Next ask · 5 · 15 · 25", value: "\(ladder.minutes) min", caption: ladder.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func promptsAndReasons(_ summary: CoachInsights.Summary) -> some View {
        HStack(alignment: .top, spacing: FFSpace.l) {
            countList(
                title: "Which prompts got you started",
                empty: "No prompts seen yet.",
                rows: summary.triggerStats.map { ($0.label.capitalizedFirst, "\($0.started) of \($0.seen)") }
            )
            Divider()
            countList(
                title: "What stops you",
                empty: "Pick a reason under “Not now, because…” and the coach adapts its next ask.",
                rows: summary.reasons.prefix(4).map { (CoachDeclineResponse.label($0.reason), "\($0.count)×") }
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func countList(title: String, empty: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.xs) {
            Text(title).ffText(.callout)
            if rows.isEmpty {
                Text(empty).ffText(.caption).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: FFSpace.s) {
                    Text(row.0).ffText(.body).lineLimit(1)
                    Spacer(minLength: FFSpace.s)
                    Text(row.1).ffText(.headline).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Coach log

    private func logDisclosure(now: Date) -> some View {
        let journal = timerVM.coachJournal.entries(on: now)
        return DisclosureGroup(isExpanded: $showLog) {
            VStack(alignment: .leading, spacing: 3) {
                if journal.isEmpty {
                    Text("Nothing yet today.").ffText(.caption)
                }
                ForEach(journal.reversed().prefix(30)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: FFSpace.s) {
                        Text(TimerViewModel.clockLabel(entry.at)).ffText(.caption).monospacedDigit()
                        Image(systemName: Self.symbol(entry.kind))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(entry.text).ffText(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, FFSpace.xs)
        } label: {
            Text("Today's coach log · why it spoke, or stayed quiet").ffText(.headline)
        }
    }

    // MARK: How the coach decides (collapsed)

    private func modelDisclosure(_ summary: CoachInsights.Summary, learning: TimerViewModel.CoachLearningSummary, snapshot: CompanionSnapshot) -> some View {
        DisclosureGroup(isExpanded: $showModel) {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                Text("The coach compares moments it prompted with moments it stayed quiet, and learns which moments and block sizes lead to a start. It starts from the research; your own starts take over.")
                    .ffText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                learnedRow(learning)
                planRow(summary)
                CoachDeliveryCharts(snapshot: snapshot, attempts: attempts)
            }
            .padding(.top, FFSpace.s)
        } label: {
            Text("How the coach decides").ffText(.headline)
        }
    }

    private func learnedRow(_ learning: TimerViewModel.CoachLearningSummary) -> some View {
        HStack(alignment: .top, spacing: FFSpace.l) {
            VStack(alignment: .leading, spacing: FFSpace.xs) {
                Text("When prompts work for you").ffText(.callout)
                if learning.effects.isEmpty {
                    Text("Starting from the research: natural breaks and your good hours help; repeats and late nights hurt.")
                        .ffText(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(learning.effects, id: \.name) { effect in
                    HStack(spacing: FFSpace.s) {
                        Image(systemName: effect.weight > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(effect.weight > 0 ? FFPalette.goal : FFPalette.atRisk)
                            .accessibilityLabel(effect.weight > 0 ? "helps" : "hurts")
                        Text(effect.name).ffText(.body)
                        Spacer(minLength: FFSpace.s)
                        Text(String(format: "%+.0f points", effect.weight * 100)).ffText(.headline).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: FFSpace.xs) {
                Text("Which size gets you started").ffText(.callout)
                Text("Score: 1 means you start, more if you keep going.").ffText(.caption)
                ForEach(learning.sizes, id: \.minutes) { size in
                    HStack(spacing: FFSpace.s) {
                        Text("\(size.minutes) min").ffText(.body)
                        Spacer(minLength: FFSpace.s)
                        Text(String(format: "%.2f", size.value)).ffText(.headline).monospacedDigit()
                        Text("· \(size.asks) asks").ffText(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func planRow(_ summary: CoachInsights.Summary) -> some View {
        HStack(alignment: .top, spacing: FFSpace.l) {
            FFStat(
                label: "Plans kept",
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
                label: "Best hour today",
                value: summary.bestHourThisWeekday.map { TimerViewModel.clockLabel($0.start) } ?? "—",
                caption: summary.bestHourThisWeekday.map { String(format: "%.1f× your average hour", $0.lift) } ?? "Needs 8 starts"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    static func symbol(_ kind: CoachJournal.Entry.Kind) -> String {
        switch kind {
        case .shown: "bubble.left.fill"
        case .quiet: "moon.zzz"
        case .started: "play.fill"
        case .declined: "hand.raised"
        case .unseen: "eye.slash"
        case .arrival: "figure.walk.arrival"
        case .logged: "checkmark.circle"
        }
    }
}

/// Start rate by prompt style, by where it appeared, and by rescue level · last 4 weeks.
private struct CoachDeliveryCharts: View {
    let snapshot: CompanionSnapshot
    let attempts: [InterventionAttempt]
    @Environment(TimerViewModel.self) private var timerVM

    var body: some View {
        let interval = DateInterval(start: snapshot.calendar.date(byAdding: .day, value: -27, to: snapshot.today.start) ?? snapshot.today.start, end: snapshot.now)
        let result = snapshot.analytics.coachEffectiveness(prompts: attempts.map(PromptSample.init), sessions: snapshot.samples, in: interval)
        let rescue = snapshot.analytics.rescueEffectiveness(
            rescues: attempts.compactMap { RescueSample(contextKey: $0.contextKey, deliveredAt: $0.deliveredAt) },
            sessions: snapshot.samples,
            in: interval
        )
        let starterMinutes = CoachStarterBlock.clampedMinutes(timerVM.settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        VStack(alignment: .leading, spacing: FFSpace.l) {
            if !result.byStyle.isEmpty {
                chart("By style · last 4 weeks", arms: result.byStyle)
            }
            if result.bySurface.count > 1 {
                chart("By where it appeared", arms: result.bySurface)
            }
            if rescue.hasRescues {
                VStack(alignment: .leading, spacing: FFSpace.s) {
                    chart("When you drift", arms: rescue.byLevel)
                    Text("In a focus window the ask shrinks: a full block, then 10 minutes, then a \(starterMinutes)-minute starter.")
                        .ffText(.caption)
                }
            }
            if rescue.starterBlocks > 0 {
                FFStat(
                    label: "\(starterMinutes)-min starts that kept going",
                    value: FFFormat.percent(rescue.keptGoingRate ?? 0),
                    caption: "\(rescue.startersKeptGoing) of \(rescue.starterBlocks) starter blocks led to 20m or more"
                )
            }
        }
    }

    private func chart(_ title: String, arms: [FocusAnalytics.PromptArm]) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            Text(title).ffText(.headline)
            PromptArmChart(arms: arms)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
