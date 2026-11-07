import SwiftUI
import SwiftData

/// The block-end window (screen audit 2026-10-28): one stage, 480 pt wide.
///
/// Header ("✦ 25m earned · Deep Work"), "Did you finish it?" for the block's task, today's tasks,
/// the project's goal, "What did this block produce?", the per-app planned/distraction review, an
/// optional time split, and a sticky footer: Break · Start next (your regular length, and the
/// coach's smaller size beside it) · Done for today.
///
/// Everything you tap saves at once (ticks, goal steps, the outcome). The tasks ticked in this
/// block become the session's achievement (history title, Calendar notes).
struct SessionCompleteWindowView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]
    @Query private var todaysTasks: [DailyTask]
    @Query private var recentSessions: [FocusSession]
    @Query private var projects: [Project]
    @Query private var goals: [ProjectGoal]

    @State private var appeared = false
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []
    @State private var hasHandledAction = false
    @State private var selectedOutcome: SessionOutcome? = nil
    /// "Not yet" on the block's task (nothing is stored; the task just stays open).
    @State private var blockTaskNotYet = false
    /// "3 blocks · 1h 40m today", read once per appearance: the last block's end moves every
    /// second of overtime, and reading it in `body` redrew the whole window each second.
    @State private var todaySummary = ""
    /// The coach's ask (the learned 5 · 15 · 25 size), read once per appearance: it runs
    /// SwiftData fetches and a model fit, so never from `body`.
    @State private var coachAsk: CoachBlockSizeLadder.Recommendation?
    /// Coach v7 §3.1: where you'll pick up. Shown when the break ends and on arrival.
    @State private var nextStepDraft = ""
    /// Coach v7: "Blocks you run 5+ min over are followed by…", read once per appearance (a fetch).
    @State private var stretchFact: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(now: Date = Date()) {
        let today = Calendar.current.startOfDay(for: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        _todaysTasks = Query(filter: #Predicate<DailyTask> { $0.day >= today })
        _recentSessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= yesterday })
    }

    private var settings: AppSettings? { allSettings.first }

    private var isBreakCompletion: Bool { timerVM.lastCompletionWasBreak }
    private var disableMotionForEvidence: Bool { reduceMotion || timerVM.isEvidenceMode }

    /// Resolved earned context — prefers durable `completedBlockContext`, falls back to legacy session info.
    private var earnedContext: (minutes: Int, projectName: String)? {
        if let ctx = timerVM.completedBlockContext {
            return (ctx.durationMinutes, ctx.projectName)
        }
        if let s = timerVM.lastCompletedFocusSession {
            return (Int(s.actualDuration / 60), s.label)
        }
        if let dur = timerVM.lastCompletedDuration {
            return (Int(dur / 60), timerVM.lastCompletedLabel ?? "Focus")
        }
        return nil
    }

    /// The project the next block continues (this block's, else the selected one).
    private var blockProjectID: UUID? {
        timerVM.lastCompletedFocusSession?.project?.id
            ?? timerVM.completedBlockContext?.projectId
            ?? timerVM.breakEpisodeContext?.earnedBlock.projectId
            ?? timerVM.selectedProject?.id
    }

    var body: some View {
        Group {
            if timerVM.isWakeRecoveryActive {
                wakeRecoveryContent
            } else if isBreakCompletion {
                breakContent
            } else {
                focusContent
            }
        }
        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
        .interactiveDismissDisabled()
        .onAppear {
            hasHandledAction = false
            showSplits = false
            splits = []
            blockTaskNotYet = false
            selectedOutcome = timerVM.lastCompletedFocusSession?.outcome
            coachAsk = timerVM.startLadderRecommendation()
            nextStepDraft = timerVM.lastCompletedFocusSession?.nextStepText ?? ""
            stretchFact = timerVM.isFocusOvertime ? timerVM.cycleStats().stretchFact : nil
            todaySummary = todayLine
            appeared = disableMotionForEvidence
            if !timerVM.isEvidenceMode {
                bringWindowToFront()
            }
            if !disableMotionForEvidence {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appeared = true }
            }
        }
        .onChange(of: blockWins) { _, _ in
            syncAchievement()
        }
        .onDisappear {
            // Ticks, goal steps and the outcome are already saved; the achievement follows the ticks.
            if !hasHandledAction { syncAchievement() }
            if !hasHandledAction, !isBreakCompletion { saveNextStep() }
            if !hasHandledAction && timerVM.isManualStop && timerVM.showSessionComplete {
                timerVM.preserveManualStop()
            }
        }
    }

    // MARK: - Wake Recovery (Issue #32)

    /// Sleep can interrupt a break as well as a block; the copy names which one it was.
    private var wakeRecoveryIsBreak: Bool {
        guard let type = timerVM.wakeRecoverySession?.type else { return false }
        return type != .focus
    }

    private var wakeRecoveryContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.amber.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .blur(radius: appeared ? 14 : 0)
                    .animation(disableMotionForEvidence ? nil : .easeOut(duration: 0.5), value: appeared)

                Image(systemName: "bed.double.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                    .accessibilityHidden(true)
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0)
            .animation(disableMotionForEvidence ? nil : FFMotion.reward, value: appeared)

            VStack(spacing: 8) {
                Text(wakeRecoveryIsBreak ? "Resolve Interrupted Break" : "Resolve Interrupted Session")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                
                Text(wakeRecoveryIsBreak
                     ? "Your break was interrupted by system sleep. Choose how you would like to resolve the break's duration."
                     : "Your focus session was interrupted by system sleep. Choose how you would like to resolve the session's duration.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }

            EvidenceSafeGlassGroup {
                VStack(spacing: 8) {
                    LiquidActionButton(
                        title: "Save up to sleep start",
                        icon: "clock.arrow.circlepath",
                        role: .primary
                    ) {
                        timerVM.resolveWakeRecovery(choice: .saveToSleepStart)
                    }

                    LiquidActionButton(
                        title: "Keep full overtime",
                        icon: "arrow.right.to.line",
                        role: .secondary
                    ) {
                        timerVM.resolveWakeRecovery(choice: .keepOvertime)
                    }

                    LiquidActionButton(
                        title: wakeRecoveryIsBreak ? "Discard this break" : "Discard this block",
                        icon: "trash",
                        role: .destructive
                    ) {
                        timerVM.resolveWakeRecovery(choice: .discard)
                        dismissWindow(id: "session-complete")
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 440)
    }

    // MARK: - Focus Completion (one stage)

    private var focusContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                earnedStage
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Fills the window (BlockEndWindowPresenter sizes it to fit the screen); scrolls above
            // the sticky footer when the content is taller.
            .frame(maxHeight: .infinity)
            footerBar
        }
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
    }

    private var earnedStage: some View {
        VStack(alignment: .leading, spacing: 20) {
            earnedHeader

            if let session = timerVM.lastCompletedFocusSession {
                if let task = blockTask(of: session) {
                    blockTaskSection(task, session: session)
                }
                SessionTasksSection(
                    sessionID: session.id,
                    blockTaskID: session.taskID,
                    projectID: session.project?.id
                )
                // After the tasks, so a tick visibly moves the bar here.
                SessionGoalSection(
                    projectID: session.project?.id, sessionID: session.id,
                    taskLinkedResultIDs: Set(todaysTasks.compactMap(\.keyResultID))
                )
                outcomeSection
            }

            // The apps seen in the block, each marked planned or a distraction: the one answer the
            // coach learns from (drift memory). Reason chips were removed (audit 2026-10-30).
            if !timerVM.lastSessionDistractingEntries.isEmpty, !timerVM.lastCompletionWasBreak {
                sessionDistractionReview
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity
                    ))
            }

            splitSection
        }
        .animation(disableMotionForEvidence ? nil : FFMotion.section, value: timerVM.lastSessionDistractingEntries.isEmpty)
        // TODO: Focus restoration on sheet dismiss for standalone windows (SessionComplete,
        // CoachIntervention) is a known limitation. Avoid NSApplication.shared.activate() here.
    }

    // MARK: Header

    /// "✦ 25m earned · Deep Work" / "45m focused · stopped early", then "3 blocks · 1h 40m today".
    private var earnedHeader: some View {
        let manual = timerVM.isManualStop
        let tint = manual ? LiquidDesignTokens.Spectral.salmon : LiquidDesignTokens.Spectral.amber
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(todaySummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .monospacedDigit()
                    .lineLimit(1)
                if let pauseLabel = timerVM.lastCompletedFocusSession?.pauseLabel ?? timerVM.lastCompletedSession?.pauseLabel {
                    Text(pauseLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .lineLimit(1)
                }
            }
            .scaleEffect(appeared ? 1 : 0.97, anchor: .leading)
            .opacity(appeared ? 1 : 0)
            .animation(disableMotionForEvidence ? nil : FFMotion.reward, value: appeared)
            Spacer(minLength: 8)
            if let eventId = timerVM.lastCompletedSession?.calendarEventId, !eventId.isEmpty {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .help("Saved to Calendar")
                    .accessibilityLabel("Saved to Calendar")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        guard let ctx = earnedContext else {
            return timerVM.isManualStop ? "Stopped early" : "✦ Block done"
        }
        return timerVM.isManualStop
            ? "\(ctx.minutes)m focused · stopped early"
            : "✦ \(ctx.minutes)m earned · \(ctx.projectName)"
    }

    /// "3 blocks · 1h 40m today"; a manual stop leads with the project (the headline has no room).
    private var todayLine: String {
        let totals = todayTotals
        var parts: [String] = []
        if timerVM.isManualStop, let name = earnedContext?.projectName { parts.append(name) }
        parts.append("\(totals.blocks) block\(totals.blocks == 1 ? "" : "s")")
        parts.append("\(FFFormat.duration(totals.seconds)) today")
        // Progress toward the goal after every block (progress principle): what is left, or met.
        let goal = timerVM.dailyGoal()
        if goal.seconds > 0 {
            let left = goal.seconds - timerVM.goalProgressSeconds()
            // The scope beside the number, as everywhere: "40m to go · ★ Learning".
            parts.append(left > 0 ? "\(FFFormat.duration(left)) to go · \(goal.label)" : "\(goal.label) goal met")
        }
        return parts.joined(separator: " · ")
    }

    /// Every kept focus block today and the time in them (same set, so the two numbers agree).
    private var todayTotals: (blocks: Int, seconds: TimeInterval) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return (timerVM.todaySessionCount, timerVM.todayFocusTime)
        }
        var kept = recentSessions.filter { Self.isKeptFocusBlock($0, from: start, to: end) }
        if let last = timerVM.lastCompletedFocusSession,
           !kept.contains(where: { $0.id == last.id }),
           Self.isKeptFocusBlock(last, from: start, to: end) {
            kept.append(last)
        }
        guard !kept.isEmpty else {
            return (max(timerVM.todaySessionCount, earnedContext == nil ? 0 : 1), timerVM.todayFocusTime)
        }
        let seconds = kept.reduce(0.0) { sum, session in
            sum + max(0, min(session.effectiveEnd, end).timeIntervalSince(max(session.startedAt, start)))
        }
        return (kept.count, seconds)
    }

    /// Mirrors `TimerViewModel.loadTodayStats`: focus blocks of 5 minutes or more that touch today.
    static func isKeptFocusBlock(_ session: FocusSession, from start: Date, to end: Date) -> Bool {
        guard session.type == .focus else { return false }
        if session.endedAt != nil, session.actualDuration < 5 * 60 { return false }
        return session.effectiveEnd > start && session.startedAt < end
    }

    // MARK: Did you finish it?

    private func blockTask(of session: FocusSession) -> DailyTask? {
        guard let taskID = session.taskID else { return nil }
        return todaysTasks.first { $0.id == taskID }
    }

    private var resultTitles: [UUID: String] {
        Dictionary(goals.flatMap(\.keyResults).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    /// The block's own task: an explicit Done or Not yet. Never ticked for you.
    private func blockTaskSection(_ task: DailyTask, session: FocusSession) -> some View {
        let finishedHere = task.isDone && task.sessionID == session.id
        let caption = SessionTasksSection.goalCaption(task, resultTitles: resultTitles)
        return VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(text: task.isCounted ? "How many did you do?" : "Did you finish it?", font: .system(size: 11, weight: .semibold), tracking: 1.8)
            if task.isCounted {
                countedBlockTask(task, session: session, caption: caption)
            } else {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .strikethrough(task.isDone, color: .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(finishedHere ? FFPalette.goal : LiquidDesignTokens.Surface.onSurfaceMuted)
                    }
                }
                Spacer(minLength: 8)
                choiceChip(
                    "Done", symbol: "checkmark", tint: LiquidDesignTokens.Spectral.mintDark,
                    selected: task.isDone, label: task.isDone ? "Mark \(task.title) not done" : "Mark \(task.title) done"
                ) {
                    withAnimation(disableMotionForEvidence ? nil : .smooth(duration: 0.25)) {
                        blockTaskNotYet = false
                        timerVM.setDailyTask(task, done: !task.isDone, sessionID: session.id)
                    }
                }
                .frame(width: 88)
                choiceChip(
                    "Not yet", symbol: "arrow.uturn.forward", tint: LiquidDesignTokens.Spectral.amberDark,
                    selected: blockTaskNotYet && !task.isDone, label: "Not finished yet, keep \(task.title) open"
                ) {
                    withAnimation(disableMotionForEvidence ? nil : .smooth(duration: 0.25)) {
                        if finishedHere { timerVM.setDailyTask(task, done: false) }
                        blockTaskNotYet = true
                    }
                }
                .frame(width: 96)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            }
            DailyTaskReceiptBanner(taskIDs: [task.id], compact: true)
        }
    }

    /// A counted block task ("Problems solved 1 of 3"): − and + log one at a time to the goal.
    private func countedBlockTask(_ task: DailyTask, session: FocusSession, caption: String?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }
            }
            Spacer(minLength: 8)
            stepButton("minus", label: "Take back 1", disabled: task.loggedCount <= 0) {
                _ = timerVM.stepDailyTask(task, by: -1, sessionID: session.id)
            }
            Text("\(DailyTaskReceipt.number(task.loggedCount)) of \(DailyTaskReceipt.number(task.progressAmount))")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(task.isDone ? FFPalette.goal : .primary)
                .contentTransition(.numericText())
                .frame(minWidth: 52)
            stepButton("plus", label: "Add 1", disabled: false) {
                _ = timerVM.stepDailyTask(task, by: 1, sessionID: session.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func stepButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(disableMotionForEvidence ? nil : .smooth(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }

    /// The tasks ticked in this block, in tick order: the session's achievement.
    private var blockWins: [String] {
        guard let sessionID = timerVM.lastCompletedFocusSession?.id else { return [] }
        return todaysTasks
            .filter { $0.isDone && $0.sessionID == sessionID }
            .sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
            .map(\.title)
    }

    private var achievementText: String? {
        let wins = blockWins
        return wins.isEmpty ? nil : wins.joined(separator: "\n")
    }

    /// Ticks save at once; the achievement follows them so history and Calendar see real wins
    /// even when the window closes without a button.
    private func syncAchievement() {
        guard !isBreakCompletion, let session = timerVM.lastCompletedFocusSession else { return }
        let text = achievementText
        guard session.achievement != text else { return }
        session.achievement = text
        try? modelContext.save()
    }

    // MARK: Outcome (Coach v2 §9 step 3)

    /// Shipped / Moved it forward / Busywork. Saved on the session and used as the coach's
    /// learning signal: real progress counts, busywork counts against the prompt that led here.
    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(
                text: "What did this block produce?",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )
            HStack(spacing: 8) {
                ForEach(SessionOutcome.allCases, id: \.self) { outcome in
                    choiceChip(
                        outcome.displayName, symbol: outcomeSymbol(outcome), tint: outcomeTint(outcome),
                        selected: selectedOutcome == outcome, label: "Rate this block: \(outcome.displayName)"
                    ) {
                        withAnimation(disableMotionForEvidence ? nil : FFMotion.control) {
                            selectedOutcome = outcome
                        }
                        timerVM.recordSessionOutcome(outcome)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choiceChip(_ title: String, symbol: String, tint: Color, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? tint : LiquidDesignTokens.Surface.onSurface.opacity(0.8))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? tint.opacity(0.16) : LiquidDesignTokens.Surface.onSurface.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.55) : LiquidDesignTokens.Surface.onSurface.opacity(0.10), lineWidth: selected ? 1 : 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func outcomeSymbol(_ outcome: SessionOutcome) -> String {
        switch outcome {
        case .shipped: "shippingbox.fill"
        case .movedForward: "arrow.forward.circle.fill"
        case .busywork: "tray.full.fill"
        }
    }

    private func outcomeTint(_ outcome: SessionOutcome) -> Color {
        switch outcome {
        case .shipped: LiquidDesignTokens.Spectral.mintDark
        case .movedForward: LiquidDesignTokens.Spectral.primaryContainer
        case .busywork: LiquidDesignTokens.Spectral.amberDark
        }
    }

    /// Inline distraction review section — shows apps seen during the session.
    private var sessionDistractionReview: some View {
        SessionDistractionReviewSection(
            entries: timerVM.lastSessionDistractingEntries,
            projectId: timerVM.completedBlockContext?.projectId,
            projectName: timerVM.completedBlockContext?.projectName
        )
    }

    // MARK: Split (disclosure)

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(disableMotionForEvidence ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
                    showSplits.toggle()
                    if showSplits && splits.isEmpty {
                        let totalMins = Int((timerVM.lastCompletedDuration ?? 0) / 60)
                        splits = [TimeSplitView.SplitEntry(
                            project: timerVM.selectedProject,
                            customLabel: timerVM.customLabel,
                            minutes: totalMins
                        )]
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showSplits ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text("Split time across projects…")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSplits ? "Hide project split" : "Split time across projects")
            .accessibilityHint("Allocate session time across multiple projects")

            if showSplits {
                TimeSplitView(
                    totalDuration: timerVM.lastCompletedDuration ?? 0,
                    splits: $splits
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: Footer (sticky)

    private var footerBar: some View {
        VStack(spacing: 8) {
            // One row: the next block and the earned break side by side, the break prominent;
            // ending below. After a block there is no smaller start: a 5-minute focus pill right
            // above "Break 5m" started a focus block when a break was meant, six times
            // (30 Oct–6 Nov 2026). The task is a caption, so no button label truncates.
            nextTaskCaption
            nextStepField
            if let stretchFact {
                Label(stretchFact, systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            EvidenceSafeGlassGroup {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        startButtons(role: .secondary, after: .block) { minutes in
                            saveAndDismiss(action: .continueFocusing, prepare: { prepareNextStart(minutes: minutes) })
                        }
                        breakButton
                    }
                    HStack(spacing: 8) {
                        LiquidActionButton(title: "Done for today", icon: "checkmark.circle", role: .secondary) {
                            saveAndDismiss(action: .endSession)
                        }
                        .accessibilityLabel("Done for today: end and keep this block")
                        if timerVM.isFocusOvertime {
                            // Coach v7 §3.1: a bounded lap, not an open-ended count-up.
                            LiquidActionButton(title: "Keep going \(CoachLanding.lapMinutes)m", icon: "forward.fill", role: .secondary) {
                                keepGoingLap()
                            }
                            .help("Ten more minutes, then this window comes back")
                            .accessibilityLabel("Keep going for \(CoachLanding.lapMinutes) more minutes")
                        }
                    }
                }
            }
            if timerVM.isManualStop {
                Button {
                    hasHandledAction = true
                    timerVM.discardManualStop()
                    dismissWindow(id: "session-complete")
                } label: {
                    Label("Discard this block", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                .accessibilityLabel("Discard this manual session")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .evidenceSafeMaterial()
    }

    /// The earned break, one click, built like every other footer pill so heights and edges match.
    /// The plain 5 minutes is in its context menu (the native split menu drew a narrower pill).
    private var breakButton: some View {
        let minutes = timerVM.suggestedEarnedBreakMinutes
        return LiquidActionButton(title: "Break \(minutes)m", icon: "cup.and.saucer.fill", role: .primary) {
            saveAndDismiss(action: .takeBreak(duration: timerVM.suggestedEarnedBreakSeconds))
        }
        .contextMenu {
            if minutes != 5 {
                Button("Break 5 min") { saveAndDismiss(action: .takeBreak(duration: 300)) }
            }
        }
        .help(minutes == 5 ? "Take a 5 minute break" : "Take the earned \(minutes) minute break. Right-click for 5 minutes.")
        .accessibilityLabel("Take the earned \(minutes) minute break")
    }

    // MARK: Next block

    /// What the next block is about: the next open task for this block's project, never another's.
    private var nextTask: DailyTask? {
        DailyTaskPlanner.nextTask(todaysTasks, on: Date(), for: blockProjectID)
    }

    /// Your regular length (`regularMinutes`), so neither a warm-up nor a long break repeats 5 or
    /// 15. Never the idle ladder from `body`: it runs SwiftData fetches and a model fit (the window
    /// froze on 2026-10-30); the coach's ask is read once into `coachAsk`.
    private var nextMinutes: Int {
        timerVM.regularMinutes
    }

    private var startTitle: String { "Start \(nextMinutes)m" }

    /// "Next: <task>" above the start pills, one line, full title on hover.
    @ViewBuilder
    private var nextTaskCaption: some View {
        if let task = nextTask {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Next: \(task.title)")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .help(task.title)
        }
    }

    /// "Start 25m" and, after a break only, the coach's smaller ask beside it at the same width.
    /// `onStart` gets the chosen size.
    private func startButtons(role: LiquidActionRole, tint: Color? = nil, after: NextStartOffer.Moment, onStart: @escaping (Int) -> Void) -> some View {
        let smallerMinutes = NextStartOffer.smallerMinutes(after: after, regular: nextMinutes, coachAsk: coachAsk?.minutes)
        return HStack(spacing: 8) {
            LiquidActionButton(title: startTitle, icon: "play.fill", role: role, tint: tint) {
                onStart(nextMinutes)
            }
            .help(nextTask.map { "\(startTitle) on \($0.title)" } ?? startTitle)
            .accessibilityLabel(nextTask.map { "\(startTitle) on \($0.title)" } ?? startTitle)
            if let small = smallerMinutes {
                let why = coachAsk?.minutes == small ? coachAsk?.caption : nil
                LiquidActionButton(title: "Start \(small)m", icon: "play", role: .secondary) {
                    onStart(small)
                }
                .help(why ?? "A smaller start: \(small) minutes")
                .accessibilityLabel("Start \(small) minutes instead")
            }
        }
    }

    /// Sets up `continueAfterCompletion(.continueFocusing)` to start `minutes` on the next task
    /// (its project too). Returns the restore step for the user's chosen duration.
    private func prepareNextStart(minutes: Int) -> () -> Void {
        let previousMinutes = timerVM.selectedMinutes
        timerVM.selectedMinutes = minutes
        if let task = nextTask {
            timerVM.pendingTaskID = task.id
            timerVM.pendingIntentText = task.title
            if let projectID = task.projectID, projectID != timerVM.selectedProject?.id,
               let project = projects.first(where: { $0.id == projectID }) {
                timerVM.selectedProject = project
            }
        }
        return { [timerVM] in timerVM.selectedMinutes = previousMinutes }
    }

    // MARK: - Break Completion

    private var breakContent: some View {
        VStack(spacing: 12) {
            breakHeaderSection
            breakActionsSection
        }
        .padding(18)
        .frame(width: 420)
    }

    private var breakHeaderSection: some View {
        VStack(spacing: 10) {
            // The only part that ticks: kept in its own view so the window doesn't re-render each second.
            BreakOverrunTitle()
            BreakOverrunQuestion()

            // Spec invariant: always show last earned block
            if let ctx = timerVM.completedBlockContext ?? timerVM.breakEpisodeContext?.earnedBlock {
                VStack(spacing: 3) {
                    Text("Last earned block")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(ctx.durationMinutes)m · \(ctx.projectName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LiquidDesignTokens.Spectral.electricBlue.opacity(0.1)))
            }
        }
        .padding(.top, 8)
    }

    private var breakActionsSection: some View {
        EvidenceSafeGlassGroup {
            VStack(spacing: 8) {
                nextTaskCaption
                startButtons(role: .primary, tint: .blue, after: .breakEnded) { minutes in
                    hasHandledAction = true
                    let restore = prepareNextStart(minutes: minutes)
                    timerVM.continueAfterCompletion(action: .continueFocusing)
                    restore()
                    dismissWindow(id: "session-complete")
                }

                LiquidActionButton(
                    title: "Done for today",
                    icon: "checkmark.circle",
                    role: .secondary
                ) {
                    hasHandledAction = true
                    timerVM.continueAfterCompletion(action: .endSession)
                    dismissWindow(id: "session-complete")
                }
                .accessibilityLabel("Done for today: end the break and keep today's progress")
            }
        }
    }

    // MARK: - Actions

    /// Saves the block's leftovers (achievement from the ticks, splits), then runs
    /// `action`. `prepare` runs just before `continueAfterCompletion` and returns its undo.
    /// "Next step" (coach v7 §3.1): one line, saved on any action or when the window closes.
    private var nextStepField: some View {
        TextField("Next step: where you'll pick up", text: $nextStepDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
            .onSubmit(saveNextStep)
            .accessibilityLabel("Next step")
            .accessibilityHint("Shown when your break ends")
    }

    private func saveNextStep() {
        guard !isBreakCompletion else { return }
        let trimmed = nextStepDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (timerVM.lastCompletedFocusSession?.nextStepText ?? "") else { return }
        timerVM.setNextStep(trimmed)
    }

    private func keepGoingLap() {
        guard !hasHandledAction else { return }
        hasHandledAction = true
        syncAchievement()
        saveNextStep()
        timerVM.keepGoingLap()
        dismissWindow(id: "session-complete")
    }

    private func saveAndDismiss(action: PostCompletionAction, prepare: (() -> (() -> Void))? = nil) {
        // The save is async, so the window stays up for a moment; a second click must not
        // save the reflection (and its splits) twice.
        guard !hasHandledAction else { return }
        hasHandledAction = true
        saveNextStep()
        let achievement = achievementText
        Task { @MainActor in
            await timerVM.saveReflection(
                achievement: achievement,
                splits: showSplits ? splits : nil
            )
            let restore = prepare?()
            timerVM.continueAfterCompletion(action: action)
            restore?()
            dismissWindow(id: "session-complete")
        }
    }

    // MARK: - Helpers

    /// To the screen you're on, in front, at a usable size (`BlockEndWindowPresenter`).
    private func bringWindowToFront() {
        let compact = isBreakCompletion || timerVM.isWakeRecoveryActive
        DispatchQueue.main.async {
            let windows = NSApplication.shared.windows
            let window = windows.first { $0.identifier?.rawValue.contains("session-complete") == true }
                ?? windows.last { $0.title == "Block complete" && $0.isVisible }
            if let window { BlockEndWindowPresenter.present(window, compact: compact) }
        }
    }
}

/// Cup and "Break ran 3m over" (amber) or "Reset complete". The only part of the break window
/// that reads the per-second overtime tick, so only this view re-renders while a break runs over.
/// Coach v6 §3.4: once a break is 5+ min over, one tap says why. The answer is stored on the
/// break and moves the next break's length (`BreakAdaptation`). Its own view: it ticks.
private struct BreakOverrunQuestion: View {
    @Environment(TimerViewModel.self) private var timerVM

    private var overSeconds: Int {
        max(timerVM.breakEpisodeContext?.overrunSeconds ?? 0, timerVM.isBreakOvertime ? timerVM.overtimeSeconds : 0)
    }

    var body: some View {
        if overSeconds >= BreakOverrunReason.askAfterSeconds {
            VStack(spacing: 6) {
                Text("What happened?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(BreakOverrunReason.allCases) { reason in
                        let picked = timerVM.breakOverrunReason == reason
                        Button { timerVM.answerBreakOverrun(reason) } label: {
                            Text(reason.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(picked ? Color.white : LiquidDesignTokens.Surface.onSurface)
                        .background(Capsule().fill(picked ? AnyShapeStyle(LiquidDesignTokens.Spectral.amber) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        .accessibilityLabel("Break ran over: \(reason.title)")
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
            .transition(.opacity)
        }
    }
}

private struct BreakOverrunTitle: View {
    @Environment(TimerViewModel.self) private var timerVM

    /// Seconds past the planned break (live while the break runs over).
    private var overSeconds: Int {
        max(timerVM.breakEpisodeContext?.overrunSeconds ?? 0, timerVM.isBreakOvertime ? timerVM.overtimeSeconds : 0)
    }

    var body: some View {
        let over = overSeconds
        let isOverrun = over > 60
        VStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 32))
                .foregroundStyle(isOverrun ? LiquidDesignTokens.Spectral.amber : .blue)
                .accessibilityHidden(true)

            Text(isOverrun ? "Break ran \(FFFormat.duration(TimeInterval(over))) over" : "Reset complete")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(isOverrun ? LiquidDesignTokens.Spectral.amber : LiquidDesignTokens.Surface.onSurface)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

/// Which sizes the window offers for the next block (pure, so it is unit-tested).
enum NextStartOffer {
    enum Moment { case block, breakEnded }

    /// After a finished block: none. You just worked a full block, so the next one is your usual
    /// length, and a 5-minute focus pill reads like the break. After a break: the coach's smaller
    /// ask, only when it learned one below your usual length (no fixed 5-minute fallback).
    static func smallerMinutes(after moment: Moment, regular: Int, coachAsk: Int?) -> Int? {
        guard moment == .breakEnded, let ask = coachAsk, ask < regular else { return nil }
        return ask
    }
}
