import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showStopConfirmation = false

    private var disableMotionForEvidence: Bool { reduceMotion || timerVM.isEvidenceMode }

    var body: some View {
        popoverShell
            .background(
                PopoverWindowAccessor { window in
                    timerVM.popoverWindow = window
                }
            )
            .task {
                timerVM.ensureConfigured(modelContext: modelContext)
                timerVM.checkDayRolloverIfNeeded()
                // Opening the popover answers the menu bar pulse; the waiting prompt card shows here.
                timerVM.noteCoachPopoverOpened()
            }
            .onChange(of: timerVM.state) { _, _ in
                showStopConfirmation = false
            }
    }

    private var popoverShell: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                headerBar

                if timerVM.isPrivate {
                    PrivacyStrip()
                        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                        .padding(.top, 12)
                }

                // Your line for today (own words first, else a verified quote), in every state.
                if timerVM.recoveryState == nil {
                    DailyReminderView(style: .strip)
                        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                        .padding(.top, 10)
                        .padding(.bottom, timerVM.state == .idle && !timerVM.isOvertime ? 0 : 12)
                }

                activeContextSection

                coachStripSection

                // Idle shows the hero instead of a 25:00 ring; active states keep the ring.
                if timerVM.state != .idle || timerVM.isOvertime {
                    timerHeroSection
                }

                stateSection

                if let error = timerVM.startError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation(FFMotion.control) {
                                timerVM.startError = nil
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                footerSection
            }
            .frame(width: 310)
        }
        .frame(width: 310)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.52))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.16),
                            Color.black.opacity(0.08),
                            Color.black.opacity(0.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 12, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Header Bar (focusing, paused, break, overtime)

    @ViewBuilder
    private var headerBar: some View {
        switch timerVM.state {
        case .focusing, .paused, .onBreak:
            headerBarContent
        case .idle:
            if timerVM.isOvertime {
                headerBarContent
            } else {
                EmptyView()
            }
        }
    }

    private var headerBarContent: some View {
        // Statistics live in the footer; the header only closes.
        HStack {
            Spacer()
            Button {
                timerVM.closePopover()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal - 12)
        .padding(.top, 6)
    }

    // MARK: - Active Context (focusing + overtime)

    /// Project title, with the block's intent under it (focusing and paused). The ring's own
    /// label says the state, so there is no "FOCUSING" / "OVERTIME" eyebrow.
    @ViewBuilder
    private var activeContextSection: some View {
        if timerVM.isOvertime {
            Text(timerVM.isFocusOvertime ? (timerVM.selectedProject?.name ?? "Focus") : "Break")
                .font(LiquidDesignTokens.Typography.headlineMedium)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                .lineLimit(1)
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal + 20)
                .padding(.bottom, 4)
        } else if timerVM.state == .focusing || timerVM.state == .paused {
            VStack(spacing: 3) {
                if timerVM.isStarterBlock {
                    TrackedLabel(
                        text: "Starter block",
                        font: LiquidDesignTokens.Typography.labelSmall,
                        color: LiquidDesignTokens.Spectral.amber,
                        tracking: 1.8
                    )
                }
                Text(timerVM.isStarterBlock ? "Plan the next step" : (timerVM.selectedProject?.name ?? "Focus"))
                    .font(LiquidDesignTokens.Typography.headlineMedium)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .lineLimit(1)
                if !timerVM.isStarterBlock, let intent = timerVM.currentIntentText, !intent.isEmpty {
                    Text(intent)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal + 20)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Timer Hero (ring only, no dots)

    private var timerHeroSection: some View {
        TimerRingView(
            progress: timerVM.progress,
            timeString: timerVM.isOvertime ? timerVM.overtimeTimeString : (timerVM.state == .idle ? defaultTimeString : timerVM.timeString),
            label: stateLabel,
            state: timerVM.state,
            isOvertime: timerVM.isOvertime,
            evidenceMode: timerVM.isEvidenceMode,
            pauseDuration: timerVM.pauseElapsed,
            pauseTimeString: timerVM.pauseTimeString,
            labelColorOverride: stateLabelColor
        )
        .padding(.top, (timerVM.state == .idle && !timerVM.isOvertime) ? 20 : 10)
        .padding(.bottom, (timerVM.state == .idle && !timerVM.isOvertime) ? 8 : 4)
    }

    // MARK: - Coach Strip (Live Risk Status)

    @ViewBuilder
    private var coachStripSection: some View {
        // Idle: the coach's hook lives in the hero (PopoverIdleHero), so nothing renders here.
        if timerVM.settings?.coachRealtimeEnabled == true, timerVM.state != .idle {
            // Only when there is something to say: never while paused, never when stable.
            let isActive = timerVM.state == .focusing && timerVM.coachEngine.riskLevel != .stable
            let overlayActive = timerVM.activeCoachPopoverDecision != nil &&
                FocusCoachPresentationMapper.mapDecision(timerVM.activeCoachPopoverDecision ?? .none) != nil

            if isActive && !overlayActive {
                let model = FocusCoachPresentationMapper.map(
                    level: timerVM.coachEngine.riskLevel,
                    score: timerVM.coachEngine.riskScore
                )
                FocusCoachStripView(model: model, onTap: {
                    openStatsWindow(requestedTab: .insights)
                })
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 4)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .animation(disableMotionForEvidence ? nil : FFMotion.warning, value: isActive)
            }

            // Quick prompt overlay when coach decides to intervene
            if let promptModel = overlayActive ? FocusCoachPresentationMapper.mapDecision(timerVM.activeCoachPopoverDecision ?? .none) : nil {
                FocusCoachQuickPromptView(
                    model: promptModel,
                    onAction: { action in
                        timerVM.handleCoachAction(action)
                    },
                    onDismiss: {
                        timerVM.dismissCoachPrompt()
                    }
                )
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
    }

    // MARK: - State Section

    @ViewBuilder
    private var stateSection: some View {
        Group {
            if timerVM.isOvertime {
                if timerVM.isFocusOvertime {
                    overtimeContent
                } else {
                    breakOvertimeContent
                }
            } else {
                switch timerVM.state {
                case .idle:
                    idleContent
                case .focusing:
                    focusingContent
                case .paused:
                    pausedContent
                case .onBreak:
                    breakContent
                }
            }
        }
        .contentTransition(.opacity)
        .transaction { t in
            // Only animate discrete state transitions, not per-second observable updates.
            // This prevents the blanket .animation() from re-triggering layout passes
            // when overtime text or progress values change every tick.
            if t.animation != nil {
                t.animation = .easeInOut(duration: 0.2)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                // The honest total (screen audit): the verdict, not one "today" number.
                Button {
                    openStatsWindow(requestedTab: .goals)
                } label: {
                    PopoverVerdictText()
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Goals: own work against your priorities")
                .accessibilityLabel("Today's verdict. Opens Goals")

                // Private now: hide FocusFlow from the menu bar, notch and pop-ups (SharePrivacy).
                Button {
                    withAnimation(FFMotion.control) { timerVM.setPrivateManually(!timerVM.isPrivateManual) }
                } label: {
                    Image(systemName: timerVM.isPrivateManual ? "eye.slash.fill" : "eye.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(timerVM.isPrivateManual ? AnyShapeStyle(.tint) : AnyShapeStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7)))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(timerVM.isPrivateManual ? "Show FocusFlow again" : "Private now: hide FocusFlow from the menu bar, notch and pop-ups")
                .accessibilityLabel(timerVM.isPrivateManual ? "Turn off private mode" : "Turn on private mode")

                Button {
                    openStatsWindow(requestedTab: nil)
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open insights")

                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Settings")
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.26))
            )
        }
    }

    // MARK: - Helpers

    /// Behavioral ring subtitle per spec §11: Ready, Protecting, Check, Return; Block done / Break over.
    /// Escalates to "Check" during active focus when guardian has surfaced a challenge.
    private var stateLabel: String {
        switch timerVM.state {
        case .idle:
            // Idle + overtime is the end of a block or a break that ran over.
            if timerVM.isOvertime { return timerVM.isFocusOvertime ? "Block done" : "Break over" }
            return "Ready"
        case .focusing:
            if timerVM.isOvertime { return "Overtime" }
            if timerVM.activeCoachInterventionDecision != nil ||
               timerVM.currentCoachQuickPromptDecision != nil {
                return "Check"
            }
            return "Protecting"
        case .paused:
            return "Check"
        case .onBreak:
            return "Return"
        }
    }

    private var stateLabelColor: Color {
        switch timerVM.state {
        case .idle:
            if timerVM.isOvertime { return timerVM.isFocusOvertime ? LiquidDesignTokens.Spectral.mint : Color.orange }
            return LiquidDesignTokens.Surface.onSurfaceMuted
        case .focusing:
            if timerVM.isOvertime { return LiquidDesignTokens.Spectral.mint }
            if timerVM.activeCoachInterventionDecision != nil || timerVM.currentCoachQuickPromptDecision != nil {
                return LiquidDesignTokens.Spectral.amber
            }
            return LiquidDesignTokens.Spectral.electricBlue
        case .paused: return LiquidDesignTokens.Spectral.amber
        case .onBreak: return LiquidDesignTokens.Spectral.mint
        }
    }

    private var defaultTimeString: String {
        let mins = max(5, timerVM.selectedMinutes)
        return String(format: "%02d:00", mins)
    }

    private func openSettingsWindow() {
        // Same activation order as openStatsWindow: promote while still inside the tap handler.
        WindowPolicyManager.shared.prepareToOpen()
        timerVM.closePopover()
        DispatchQueue.main.async {
            openSettings()
        }
    }

    private func openStatsWindow(requestedTab: CompanionTab?) {
        if let requestedTab {
            UserDefaults.standard.set(requestedTab.rawValue, forKey: "companionRequestedTab")
        }
        // Pre-promote while FocusFlow is still active (we're inside a button-tap handler).
        // Calling this after the popover closes is too late — Tahoe blocks activation then.
        WindowPolicyManager.shared.prepareToOpen()
        // Close popover after pre-promoting so the policy change happens in user-event context.
        timerVM.closePopover()
        DispatchQueue.main.async {
            openWindow(id: "stats")
        }
    }
}

// MARK: - Idle State

private struct IdlePopoverContent: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onStartFocus: () -> Void
    let onResumeRecovery: () -> Void
    let onDiscardRecovery: () -> Void

    @State private var showCustomSlider: Bool = false
    @State private var startCommitting: Bool = false
    /// The coach's learned size (`startLadderRecommendation`), marked with a sparkle.
    @State private var suggestion: CoachBlockSizeLadder.Recommendation?
    /// Today's lever (first of `GoalDataBuilder.levers`): the hero and the goal field share it.
    @State private var lever: DailyLever?
    /// The lever text this view put in the goal field, so it can be replaced but never user text.
    @State private var autoIntent: String?

    /// 5 · 15 · 25, plus your regular length when it is another size (e.g. 45).
    static func presets(regular: Int) -> [Int] {
        CoachBlockSizeLadder.sizes.contains(regular) ? CoachBlockSizeLadder.sizes : (CoachBlockSizeLadder.sizes + [regular]).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Crash recovery banner — highest priority
            if let recovery = timerVM.recoveryState {
                recoveryBanner(recovery)
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                // 1 · Hero (mirrors the notch): own-work ring, coach hook, today's lever.
                PopoverIdleHero(lever: lever)
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 16)
                // 2 · Today's tasks: tick, or click a title to make it the block's goal.
                PopoverTasksStrip()
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 14) {
                workingOnSection
                intentSection
                sizeSection
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            .padding(.top, 12)

            // "Plan for later" lives in the coach's plan card, where it is asked for; opening the
            // popover is a moment to start, not to schedule.
            VStack(spacing: 2) {
                startButton
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
        .task(id: refreshKey) {
            refresh()
        }
        // Your regular length is preselected when the popover opens and after each block, never
        // on a task change, so a pill you just tapped stays put. The coach's size has the sparkle.
        .onAppear {
            preselectRegularLength()
            timerVM.scheduleReminderSync()
        }
        .onChange(of: timerVM.completedFocusSessions) { _, _ in preselectRegularLength() }
        .onChange(of: timerVM.selectedProject) { _, newValue in
            if newValue != nil { timerVM.noteProjectSelected() }
            applyIntentPrefill()
        }
        .onChange(of: timerVM.pendingIntentText) { _, newValue in
            // Typing something else unlinks the picked task.
            guard let id = timerVM.pendingTaskID,
                  let task = timerVM.todayTasks().first(where: { $0.id == id }),
                  task.title != newValue else { return }
            timerVM.pendingTaskID = nil
        }
    }

    /// Re-read the lever and the suggestion after each block and each task change.
    private var refreshKey: String {
        "\(timerVM.completedFocusSessions)-\(timerVM.dailyTaskRevision)"
    }

    private func refresh() {
        lever = timerVM.todayLevers().first
        let recommendation = timerVM.startLadderRecommendation(now: Date())
        suggestion = recommendation
        applyIntentPrefill()
    }

    /// (Preselecting the coach's size here overwrote 25 with 5 after declined prompts.)
    private func preselectRegularLength() {
        guard !showCustomSlider else { return }
        timerVM.selectedMinutes = timerVM.regularMinutes
    }

    // MARK: Goal for this block

    /// Prefill order: the picked task, else today's lever (for this project), else the last
    /// intent (the view model's prefill). Text the user typed is never replaced.
    private func applyIntentPrefill() {
        guard timerVM.state == .idle, !timerVM.isOvertime else { return }
        let current = timerVM.pendingIntentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = timerVM.pendingTaskID, let task = timerVM.todayTasks().first(where: { $0.id == id && !$0.isDone }) {
            if current.isEmpty { timerVM.pendingIntentText = task.title }
            return
        }
        timerVM.pendingTaskID = nil
        let lastIntent = CoachHistoryReader(modelContext: modelContext).lastIntent(projectID: timerVM.selectedProject?.id) ?? ""
        let isAuto = current.isEmpty || current == lastIntent || current == autoIntent
        guard isAuto, let lever else { return }
        // The lever's goal already has a task today: the block is for that task, so its end asks
        // "How many did you do?" and the count lands on the task and the goal together.
        if let task = timerVM.todayTasks().first(where: { $0.keyResultID == lever.id && !$0.isDone }),
           timerVM.selectedProject == nil || task.projectID == nil || task.projectID == timerVM.selectedProject?.id {
            pickTask(task)
            autoIntent = task.title
            return
        }
        let projectID = timerVM.selectedProject?.id
        guard projectID == nil || lever.projectID == nil || lever.projectID == projectID else {
            // Another project's lever: fall back to this project's last intent.
            if current == autoIntent { timerVM.pendingIntentText = lastIntent }
            autoIntent = nil
            return
        }
        autoIntent = lever.action
        timerVM.pendingIntentText = lever.action
        // The lever belongs to a project: a block on it should count there.
        if projectID == nil, let leverProjectID = lever.projectID,
           let project = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == leverProjectID })))?.first {
            timerVM.selectedProject = project
        }
    }

    private func pickTask(_ task: DailyTask) {
        timerVM.pendingTaskID = task.id
        timerVM.pendingIntentText = task.title
        autoIntent = nil
        if let projectID = task.projectID,
           let project = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })))?.first {
            timerVM.selectedProject = project
        }
    }

    private func pickLever(_ lever: DailyLever) {
        timerVM.pendingTaskID = nil
        timerVM.pendingIntentText = lever.action
        autoIntent = lever.action
        if let projectID = lever.projectID,
           let project = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })))?.first {
            timerVM.selectedProject = project
        }
    }

    // MARK: Sections

    private var workingOnSection: some View {
        @Bindable var vm = timerVM
        return VStack(alignment: .leading, spacing: 6) {
            IdleSectionLabel("Working on")
            ProjectPickerView(selectedProject: $vm.selectedProject)
        }
    }

    private var intentSection: some View {
        @Bindable var vm = timerVM
        return SessionIntentField(
            intentText: $vm.pendingIntentText,
            isTaskLinked: timerVM.pendingTaskID != nil,
            openTasks: timerVM.todayTasks().filter { !$0.isDone },
            lever: lever,
            onPickTask: pickTask,
            onPickLever: pickLever
        )
    }

    private var sizeSection: some View {
        @Bindable var vm = timerVM
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                IdleSectionLabel("Size")
                Spacer()
                if showCustomSlider {
                    Text("\(timerVM.selectedMinutes) min")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Spectral.primaryContainer)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else if let suggestion {
                    Text("\(suggestion.minutes) min suggested")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .help(suggestion.caption)
                }
            }

            BlockSizeRow(
                presets: Self.presets(regular: timerVM.regularMinutes),
                suggested: suggestion?.minutes,
                selectedMinutes: $vm.selectedMinutes,
                isCustomActive: $showCustomSlider
            )

            if showCustomSlider {
                customSlider
                    .transition(.opacity)
            }
        }
    }

    private var customSlider: some View {
        Slider(value: Binding(
            get: { Double(timerVM.selectedMinutes) },
            set: { timerVM.selectedMinutes = Int($0) }
        ), in: 5...120, step: 1)
        .tint(LiquidDesignTokens.Spectral.primaryContainer)
        .accessibilityLabel("Focus duration")
        .accessibilityValue("\(timerVM.selectedMinutes) minutes")
    }

    private var startButton: some View {
        GradientCTAButton(
            title: "Start \(max(5, timerVM.selectedMinutes)) min",
            icon: "play.fill",
            gradient: LiquidDesignTokens.Gradient.focus,
            action: {
                if !reduceMotion {
                    withAnimation(FFMotion.commit) { startCommitting = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onStartFocus()
                        startCommitting = false
                    }
                } else {
                    onStartFocus()
                }
            }
        )
        .scaleEffect(startCommitting ? 0.95 : 1.0)
        .animation(reduceMotion ? nil : FFMotion.commit, value: startCommitting)
    }

    private func recoveryBanner(_ recovery: CrashRecoveryState) -> some View {
        let remaining = Int(recovery.remainingSeconds)
        let mins = remaining / 60
        let secs = remaining % 60
        let timeString = String(format: "%d:%02d", mins, secs)
        let minutesAgo = Int(Date().timeIntervalSince(recovery.checkpointDate) / 60)
        let agoText = minutesAgo < 1 ? "just now" : "\(minutesAgo)m ago"
        let projectName = timerVM.recoveryProject?.name ?? recovery.customLabel ?? "Focus"
        let totalMins = Int(recovery.totalSeconds / 60)

        return VStack(spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Session Interrupted")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text(agoText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(totalMins)-min session · \(timeString) remaining\(recovery.isPaused ? " · paused" : "")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

    // Action buttons
            HStack(spacing: 8) {
                Button(action: onResumeRecovery) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .accessibilityHidden(true)
                        Text("Resume Session")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        Capsule(style: .continuous)
                            .fill(LiquidDesignTokens.Gradient.focus)
                    }
                    .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume recovered session")

                Button(action: onDiscardRecovery) {
                    Text("Discard")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard recovered session")
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.orange.opacity(0.4), .orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }

}

// MARK: - Intent Capture (Coach v2 §9 step 2)

/// Section label in sentence case, 11 pt semibold, secondary colour. Shared by the idle sections.
private struct IdleSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// "Goal for this block": prefilled with the picked task, else today's lever, else the last
/// intent. The trailing menu offers today's open tasks, then the lever. Start never waits on it.
private struct SessionIntentField: View {
    @Binding var intentText: String
    let isTaskLinked: Bool
    let openTasks: [DailyTask]
    let lever: DailyLever?
    let onPickTask: (DailyTask) -> Void
    let onPickLever: (DailyLever) -> Void

    /// The lever, unless it is already one of today's tasks.
    private var menuLever: DailyLever? {
        guard let lever, !openTasks.contains(where: { $0.title == lever.action }) else { return nil }
        return lever
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IdleSectionLabel("Goal for this block")
            HStack(spacing: 8) {
                Image(systemName: isTaskLinked ? "checklist.checked" : "checkmark.seal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isTaskLinked ? FFPalette.accent : LiquidDesignTokens.Surface.onSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("e.g. Draft the intro section (optional)", text: $intentText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .accessibilityLabel("Goal for this block")
                if !openTasks.isEmpty || menuLever != nil {
                    Menu {
                        if !openTasks.isEmpty {
                            Section("Today's tasks") {
                                ForEach(openTasks) { task in
                                    Button(task.title) { onPickTask(task) }
                                }
                            }
                        }
                        if let lever = menuLever {
                            Section("Today's lever") {
                                Button(lever.action) { onPickLever(lever) }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .help("Pick one of today's tasks or the lever")
                    .accessibilityLabel("Pick a goal from today's tasks")
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
            .frame(height: 30)
            .evidenceSafeGlass(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
        }
    }
}

/// 5 · 15 · 25 · Custom. The coach's suggestion carries a small sparkle.
private struct BlockSizeRow: View {
    let presets: [Int]
    let suggested: Int?
    @Binding var selectedMinutes: Int
    @Binding var isCustomActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    pill(minutes)
                }
                customPill
            }
        }
    }

    @ViewBuilder
    private func pill(_ minutes: Int) -> some View {
        let isSelected = !isCustomActive && selectedMinutes == minutes
        let button = Button {
            withAnimation(reduceMotion ? nil : FFMotion.control) {
                selectedMinutes = minutes
                isCustomActive = false
            }
        } label: {
            HStack(spacing: 3) {
                Text("\(minutes)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if minutes == suggested {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonBorderShape(.capsule)
        .accessibilityLabel(minutes == suggested ? "\(minutes) minutes, suggested" : "\(minutes) minutes")
        if isSelected {
            button.buttonStyle(.glassProminent).tint(LiquidDesignTokens.Spectral.primaryContainer)
        } else {
            button.buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var customPill: some View {
        let button = Button {
            withAnimation(reduceMotion ? nil : FFMotion.section) { isCustomActive = true }
        } label: {
            Text("Custom")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Custom duration")
        if isCustomActive {
            button.buttonStyle(.glassProminent).tint(LiquidDesignTokens.Spectral.primaryContainer)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

/// The footer's honest total: "3h 50m tracked · 50m on your #1 · 22% own work".
/// Re-reads the store only when today's focus time or the block count changes.
private struct PopoverVerdictText: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let _ = (timerVM.todayFocusTime, timerVM.completedFocusSessions)
        let verdict = TodayVerdict.text(modelContext: modelContext)
        Text(verdict ?? "Nothing tracked yet today")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(LiquidDesignTokens.Surface.onSurface.opacity(verdict == nil ? 0.55 : 0.8))
            .monospacedDigit()
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Duration control



// MARK: - Starter block

/// "What's the very next step?" during a starter block. Saved as the block's intent and offered
/// as "Keep going: 20m on {step}?" when it ends.
private struct StarterStepField: View {
    @Binding var step: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What's the very next step?")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                    .accessibilityHidden(true)
                TextField("e.g. Sketch the onboarding empty state", text: $step)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .focused($focused)
                    .accessibilityLabel("The very next step")
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .evidenceSafeGlass(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
            Text("Small and concrete. When the timer ends you can keep going on it.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }
}

// MARK: - Focusing State

private struct FocusingPopoverContent: View {
    @Binding var showStopConfirmation: Bool
    @Binding var selectedProject: Project?
    var isStarterBlock: Bool = false
    var starterStep: Binding<String> = .constant("")
    /// The running block's length and which sizes it can take (`TimerViewModel.setBlockLength`).
    let blockMinutes: Int
    let regularMinutes: Int
    let canSetLength: (Int) -> Bool
    let cycleProgress: Double
    let onPause: () -> Void
    let onSetLength: (Int) -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void
    let onSwitchProject: (Project?) -> Void

    @State private var saveAnimating = false
    @State private var discardAnimating = false
    @State private var showProjectSwitcher = false
    @State private var switchTarget: Project?

    var body: some View {
        VStack(spacing: 12) {
            // Starter block: one prompt, one field. The step becomes the next block's intent.
            if isStarterBlock {
                StarterStepField(step: starterStep)
                    .padding(.top, 10)
            }

            // Pause / Stop buttons — native glass
            HStack(spacing: 12) {
                GradientCTAButton(
                    title: "Pause",
                    icon: "pause.fill",
                    gradient: LiquidDesignTokens.Gradient.pause,
                    foregroundColor: .white,
                    action: onPause
                )
                .accessibilityLabel("Pause focus session")

                GradientCTAButton(
                    title: "Stop",
                    icon: "stop.fill",
                    gradient: LiquidDesignTokens.Gradient.stop,
                    action: { withAnimation(FFMotion.section) { onShowStopConfirmation() } }
                )
                .accessibilityLabel("Stop focus session")
            }
            .padding(.top, 14)

            // Block length: 5 · 15 · 25. Grows a warm-up in place and becomes the regular length.
            if !isStarterBlock {
                lengthRow
                    .padding(.top, 8)
            }

            // Switch project inline flow (a starter block needs no project)
            if isStarterBlock {
                EmptyView()
            } else if showProjectSwitcher {
                projectSwitcherInline
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                Button {
                    withAnimation(FFMotion.section) { showProjectSwitcher = true }
                } label: {
                    Label("Switch Project", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 34)
                .accessibilityLabel("Switch to a different project")
            }

            if showStopConfirmation {
                stopConfirmation
            }

            // Log while you work: the block's task tick and the key result's +1.
            if !isStarterBlock {
                PopoverBlockLogRow()
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    /// 5 · 15 · 25, your regular length and this block's length, once each.
    private var lengthOptions: [Int] {
        Array(Set(IdlePopoverContent.presets(regular: regularMinutes) + [blockMinutes])).sorted()
    }

    private var lengthRow: some View {
        HStack(spacing: 6) {
            Text("Length")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
            GlassEffectContainer {
                HStack(spacing: 6) {
                    ForEach(lengthOptions, id: \.self) { minutes in
                        lengthPill(minutes)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lengthPill(_ minutes: Int) -> some View {
        let isCurrent = minutes == blockMinutes
        let enabled = isCurrent || canSetLength(minutes)
        let button = Button { onSetLength(minutes) } label: {
            Text("\(minutes)m")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonBorderShape(.capsule)
        .disabled(!enabled || isCurrent)
        .opacity(enabled ? 1 : 0.38)
        .accessibilityLabel(isCurrent ? "Block length \(minutes) minutes, current" : "Make this block \(minutes) minutes")
        .help(isCurrent ? "This block's length"
              : !enabled ? "Less than a minute would be left"
              : minutes >= TimerViewModel.smallestRegularMinutes ? "Make this block \(minutes) minutes, and use \(minutes) for the next blocks"
              : "Make just this block \(minutes) minutes")
        if isCurrent {
            button.buttonStyle(.glassProminent).tint(LiquidDesignTokens.Spectral.primaryContainer)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var projectSwitcherInline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Switch to:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                Spacer()
                Button {
                    withAnimation(FFMotion.section) { showProjectSwitcher = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close project switcher")
            }

            ProjectPickerView(selectedProject: $switchTarget)

            GradientCTAButton(
                title: "Continue",
                icon: "arrow.right",
                gradient: LiquidDesignTokens.Gradient.focus,
                action: {
                    guard switchTarget?.id != selectedProject?.id else {
                        withAnimation(FFMotion.section) { showProjectSwitcher = false }
                        return
                    }
                    withAnimation(FFMotion.section) {
                        showProjectSwitcher = false
                        onSwitchProject(switchTarget)
                    }
                }
            )
            .disabled(switchTarget == nil || switchTarget?.id == selectedProject?.id)
            .opacity((switchTarget == nil || switchTarget?.id == selectedProject?.id) ? 0.5 : 1.0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.06))
                .strokeBorder(Color.blue.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var stopConfirmation: some View {
        VStack(spacing: 10) {
            Text("End this session?")
                .font(LiquidDesignTokens.Typography.labelLarge)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

            GradientCTAButton(
                title: cycleProgress >= 1.0 ? "Complete Focus Block 🎉" : "Save & End",
                icon: cycleProgress >= 1.0 ? "checkmark.seal.fill" : "square.and.arrow.down",
                gradient: LiquidDesignTokens.Gradient.cycleCompletion(progress: cycleProgress)
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    saveAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSaveStop()
                }
            }
            .scaleEffect(saveAnimating ? 0.92 : 1.0)
            .opacity(saveAnimating ? 0.7 : 1.0)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    discardAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onDiscardStop()
                }
            } label: {
                Label("Discard Session", systemImage: "trash")
                    .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .scaleEffect(discardAnimating ? 0.92 : 1.0)
            .opacity(discardAnimating ? 0.5 : 1.0)
            .accessibilityLabel("Discard current focus session")

            Button {
                withAnimation(FFMotion.control) { onCancelStop() }
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Cancel ending this session")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }
}

// MARK: - Paused State

private struct PausedPopoverContent: View {
    let pauseTimeString: String
    let pauseWarningColor: Color
    let pauseWarningMessage: String
    @Binding var showStopConfirmation: Bool
    let cycleProgress: Double
    let onResume: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void

    @State private var saveAnimating = false
    @State private var discardAnimating = false

    var body: some View {
        VStack(spacing: 14) {
            // Escalating motivational nudge based on pause duration
            Text(pauseWarningMessage)
                .font(LiquidDesignTokens.Typography.bodySmall)
                .foregroundStyle(pauseWarningColor)
                .italic()
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.4), value: pauseWarningMessage)

            // Resume CTA — amber gradient
            GradientCTAButton(
                title: "Resume Focus",
                icon: "play.fill",
                gradient: LiquidDesignTokens.Gradient.resume,
                foregroundColor: .white,
                action: onResume
            )

            // End Session — plain text link
            Button {
                withAnimation(FFMotion.section) { onShowStopConfirmation() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    TrackedLabel(
                        text: "End Session",
                        font: LiquidDesignTokens.Typography.labelMedium,
                        color: LiquidDesignTokens.Surface.onSurfaceMuted,
                        tracking: 2.0
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End paused session")

            if showStopConfirmation {
                pausedStopConfirmation
            }

            PopoverBlockLogRow()
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private var pausedStopConfirmation: some View {
        VStack(spacing: 8) {
            GradientCTAButton(
                title: cycleProgress >= 1.0 ? "Complete Focus Block 🎉" : "Save & End",
                icon: cycleProgress >= 1.0 ? "checkmark.seal.fill" : "square.and.arrow.down",
                gradient: LiquidDesignTokens.Gradient.cycleCompletion(progress: cycleProgress)
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    saveAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSaveStop()
                }
            }
            .scaleEffect(saveAnimating ? 0.92 : 1.0)
            .opacity(saveAnimating ? 0.7 : 1.0)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    discardAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onDiscardStop()
                }
            } label: {
                Label("Discard Session", systemImage: "trash")
                    .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .scaleEffect(discardAnimating ? 0.92 : 1.0)
            .opacity(discardAnimating ? 0.5 : 1.0)
            .accessibilityLabel("Discard paused session")

            Button {
                withAnimation(FFMotion.control) { onCancelStop() }
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Cancel paused stop confirmation")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }
}

// MARK: - Overtime State

private struct OvertimePopoverContent: View {
    @Binding var selectedProject: Project?
    let showSessionComplete: Bool
    let onLogBlock: () -> Void
    let onTakeBreak: () -> Void
    let onKeepGoing: () -> Void
    let onEnd: () -> Void

    var body: some View {
        // The ring already shows "+M:SS · Block done"; no badge repeats it.
        VStack(spacing: 12) {
            Text("Block done. Log it, then keep going or rest.")
                .font(.system(size: 12))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            GradientCTAButton(
                title: "Log this block",
                icon: "checkmark.circle",
                gradient: LiquidDesignTokens.Gradient.focus,
                action: onLogBlock
            )

            if !showSessionComplete {
                // The block-end window was closed: the other answers stay one click away.
                GlassEffectContainer {
                    HStack(spacing: 6) {
                        secondaryButton("Break 5 min", label: "Take a 5 minute break", action: onTakeBreak)
                        secondaryButton("Keep going", label: "Start the next block", action: onKeepGoing)
                        secondaryButton("End", label: "End without logging", action: onEnd)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    TrackedLabel(
                        text: "Next Session Project",
                        font: .system(size: 10, weight: .medium),
                        tracking: 1.8
                    )
                    ProjectPickerView(selectedProject: $selectedProject)
                }
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private func secondaryButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(label)
    }
}

// MARK: - Break Overtime State

private struct BreakOvertimePopoverContent: View {
    /// "Next: 3 LeetCode questions": the picked task, else today's lever.
    let nextLine: String?
    let onStartFocusing: () -> Void
    let onEnd: () -> Void

    var body: some View {
        // The ring already shows the overrun and "Break over"; no badge repeats it.
        VStack(spacing: 12) {
            if let nextLine {
                Text("Next: \(nextLine)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            GlassEffectContainer {
                VStack(spacing: 8) {
                    GradientCTAButton(
                        title: "Start Next Block",
                        icon: "play.fill",
                        gradient: LiquidDesignTokens.Gradient.focus,
                        action: onStartFocusing
                    )

                    Button(action: onEnd) {
                        TrackedLabel(
                            text: "End Break",
                            font: LiquidDesignTokens.Typography.labelMedium,
                            color: LiquidDesignTokens.Surface.onSurfaceMuted,
                            tracking: 2.0
                        )
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("End break")
                }
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }
}

// MARK: - Break State

private struct BreakPopoverContent: View {
    @Binding var selectedProject: Project?
    let isBreakPaused: Bool
    let onSkipBreak: () -> Void
    let onEndSession: () -> Void
    let onPauseBreak: () -> Void
    let onResumeBreak: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Next session project picker
            VStack(spacing: 6) {
                HStack {
                    TrackedLabel(
                        text: "Next Session Project",
                        font: .system(size: 10, weight: .medium),
                        tracking: 1.8
                    )
                    Spacer()
                }
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)

                ProjectPickerView(selectedProject: $selectedProject)
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            }
            .padding(.top, 8)

            GlassEffectContainer {
                VStack(spacing: 8) {
                    // Primary CTA — start next focus block (spec: "Start focusing")
                    Button(action: onSkipBreak) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                            Text("Start Focusing")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Skip break and start next focus block")

                    // Secondary actions row
                    HStack(spacing: 8) {
                        // Pause / Resume break toggle (spec: "Pause break")
                        if isBreakPaused {
                            Button(action: onResumeBreak) {
                                HStack(spacing: 5) {
                                    Image(systemName: "play.circle")
                                        .font(.system(size: 11))
                                        .accessibilityHidden(true)
                                    Text("Resume Break")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .accessibilityLabel("Resume break countdown")
                        } else {
                            Button(action: onPauseBreak) {
                                HStack(spacing: 5) {
                                    Image(systemName: "pause.circle")
                                        .font(.system(size: 11))
                                        .accessibilityHidden(true)
                                    Text("Pause Break")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .accessibilityLabel("Pause break countdown")
                        }

                        // End session (spec: "End session")
                        Button(action: onEndSession) {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                    .accessibilityHidden(true)
                                Text("End Session")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel("End session and return to idle")
                    }
                }
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - MenuBarPopoverView State Wiring

extension MenuBarPopoverView {
    fileprivate var idleContent: some View {
        IdlePopoverContent(
            onStartFocus: {
                timerVM.ensureConfigured(modelContext: modelContext)
                timerVM.startFocus()
            },
            onResumeRecovery: {
                timerVM.resumeFromRecovery()
            },
            onDiscardRecovery: {
                timerVM.discardRecovery()
            }
        )
    }

    fileprivate var focusingContent: some View {
        @Bindable var vm = timerVM
        return FocusingPopoverContent(
            showStopConfirmation: $showStopConfirmation,
            selectedProject: $vm.selectedProject,
            isStarterBlock: timerVM.isStarterBlock,
            starterStep: $vm.starterStepText,
            blockMinutes: timerVM.blockLengthMinutes,
            regularMinutes: timerVM.regularMinutes,
            canSetLength: { timerVM.canSetBlockLength($0) },
            cycleProgress: timerVM.cycleProgress,
            onPause: { timerVM.pause() },
            onSetLength: { minutes in
                withAnimation(FFMotion.control) { _ = timerVM.setBlockLength(minutes: minutes) }
            },
            onShowStopConfirmation: {
                withAnimation { showStopConfirmation = true }
            },
            onSaveStop: { timerVM.stopForReflection() },
            onDiscardStop: { timerVM.abandonSession() },
            onCancelStop: { showStopConfirmation = false },
            onSwitchProject: { project in timerVM.switchProject(to: project) }
        )
    }

    fileprivate var pausedContent: some View {
        PausedPopoverContent(
            pauseTimeString: timerVM.pauseTimeString,
            pauseWarningColor: timerVM.pauseWarningLevel.color,
            pauseWarningMessage: timerVM.pauseWarningMessage,
            showStopConfirmation: $showStopConfirmation,
            cycleProgress: timerVM.cycleProgress,
            onResume: { timerVM.resume() },
            onShowStopConfirmation: {
                withAnimation { showStopConfirmation = true }
            },
            onSaveStop: { timerVM.stopForReflection() },
            onDiscardStop: { timerVM.abandonSession() },
            onCancelStop: { showStopConfirmation = false }
        )
    }

    fileprivate var breakContent: some View {
        @Bindable var vm = timerVM
        return BreakPopoverContent(
            selectedProject: $vm.selectedProject,
            isBreakPaused: timerVM.isBreakPaused,
            onSkipBreak: { timerVM.skipBreak() },
            onEndSession: { timerVM.stop() },
            onPauseBreak: { timerVM.pauseBreak() },
            onResumeBreak: { timerVM.resumeBreak() }
        )
    }

    fileprivate var breakOvertimeContent: some View {
        BreakOvertimePopoverContent(
            nextLine: nextStepLine,
            onStartFocusing: {
                timerVM.continueAfterCompletion(action: .continueFocusing)
            },
            onEnd: {
                timerVM.continueAfterCompletion(action: .endSession)
            }
        )
    }

    /// What the next block is about: the picked task, else today's lever.
    fileprivate var nextStepLine: String? {
        if let id = timerVM.pendingTaskID, let task = timerVM.todayTasks().first(where: { $0.id == id && !$0.isDone }) {
            return task.title
        }
        return timerVM.todayLevers().first?.action
    }

    fileprivate var overtimeContent: some View {
        @Bindable var vm = timerVM
        return OvertimePopoverContent(
            selectedProject: $vm.selectedProject,
            showSessionComplete: timerVM.showSessionComplete,
            onLogBlock: {
                timerVM.openCompletionWindow?()
                timerVM.requestAppActivation?()
            },
            onTakeBreak: {
                timerVM.continueAfterCompletion(action: .takeBreak(duration: 300))
            },
            onKeepGoing: {
                timerVM.continueAfterCompletion(action: .continueFocusing)
            },
            onEnd: {
                timerVM.continueAfterCompletion(action: .endSession)
            }
        )
    }
}

/// Shown while FocusFlow hides itself (SharePrivacy): says why, and how to come back.
private struct PrivacyStrip: View {
    @Environment(TimerViewModel.self) private var timerVM

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hidden while you share")
                    .font(.system(size: 12, weight: .semibold))
                Text(timerVM.isPrivateManual
                     ? "Menu bar, notch, pop-ups and alerts stay quiet until you turn this off."
                     : "Your screen is being shared. FocusFlow comes back when the share ends.")
                    .font(.system(size: 11))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if timerVM.isPrivateManual {
                Button("Show") { timerVM.setPrivateManually(false) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}
