import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showStopConfirmation = false

    var body: some View {
        popoverShell
            .background(
                PopoverWindowAccessor { window in
                    timerVM.popoverWindow = window
                }
            )
            .task {
                timerVM.ensureConfigured(modelContext: modelContext)
            }
            .onChange(of: timerVM.state) { _, _ in
                showStopConfirmation = false
            }
    }

    private var popoverShell: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                headerBar

                activeContextSection

                coachStripSection

                timerHeroSection

                earnedTokenBadge

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
        HStack {
            Spacer()
            HStack(spacing: 12) {
                Button {
                    openStatsWindow(requestedTab: nil)
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open statistics")

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
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Active Context (focusing + overtime)

    @ViewBuilder
    private var activeContextSection: some View {
        if case .focusing = timerVM.state {
            VStack(spacing: 3) {
                TrackedLabel(
                    text: "Focusing",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    color: LiquidDesignTokens.Spectral.electricBlue,
                    tracking: 1.8
                )
                Text(timerVM.selectedProject?.name ?? "Focus")
                    .font(LiquidDesignTokens.Typography.headlineMedium)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .lineLimit(1)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
        } else if timerVM.isOvertime {
            VStack(spacing: 3) {
                TrackedLabel(
                    text: timerVM.isFocusOvertime ? "Overtime" : "Break Over",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    color: timerVM.isFocusOvertime ? LiquidDesignTokens.Spectral.mint : Color.orange,
                    tracking: 1.8
                )
                Text(timerVM.isFocusOvertime ? (timerVM.selectedProject?.name ?? "Focus") : "Break")
                    .font(LiquidDesignTokens.Typography.headlineMedium)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .lineLimit(1)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Earned Token Badge (shown after block completes, until next session starts)

    @ViewBuilder
    private var earnedTokenBadge: some View {
        if let ctx = timerVM.completedBlockContext, timerVM.state != .focusing {
            HStack(spacing: 4) {
                Text("✦ \(ctx.durationMinutes)m earned")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Spectral.mint)
                    .contentTransition(.numericText(countsDown: false))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(0.12))
                    .overlay(Capsule().strokeBorder(LiquidDesignTokens.Spectral.mint.opacity(0.18), lineWidth: 0.5))
            )
            .transition(.asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(FFMotion.reward, value: ctx.durationMinutes)
            .padding(.bottom, 2)
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
        if timerVM.settings?.coachRealtimeEnabled == true {
            let isActive: Bool = {
                switch timerVM.state {
                case .focusing, .paused: return true
                case .onBreak: return true
                case .idle: return false
                }
            }()
            let overlayActive = timerVM.activeCoachPopoverDecision != nil &&
                FocusCoachPresentationMapper.mapDecision(timerVM.activeCoachPopoverDecision ?? .none) != nil

            if isActive && !overlayActive {
                let model = FocusCoachPresentationMapper.map(
                    level: timerVM.coachEngine.riskLevel,
                    score: timerVM.coachEngine.riskScore
                )
                FocusCoachStripView(model: model)
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 4)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .animation(FFMotion.warning, value: isActive)
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

                if timerVM.state == .idle {
                    VStack(alignment: .leading, spacing: 4) {
                        if let summary = timerVM.idleStarterSummary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let recommended = timerVM.idleStarterRecommendedMinutes {
                            Text("Recommended duration: \(recommended)m")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                }
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
            HStack(spacing: 8) {
                footerLeadingContent

                Spacer()

                Text(timerVM.todayFocusTime.formattedFocusTime)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(footerTimeColor)
                    .monospacedDigit()

                Button {
                    openStatsWindow(requestedTab: .settings)
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

    @ViewBuilder
    private var footerLeadingContent: some View {
        switch timerVM.state {
        case .focusing:
            Text("TODAY'S TOTAL")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
        case .paused:
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: 0xE6A820))
                    .frame(width: 6, height: 6)
                Text("TODAY'S TOTAL")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
            }
        case .onBreak:
            Text("TODAY'S TOTAL")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
        default:
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                    .accessibilityHidden(true)
                Text("TODAY'S TOTAL")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface.opacity(0.8))
            }
        }
    }

    private var footerTimeColor: Color {
        switch timerVM.state {
        case .focusing:
            LiquidDesignTokens.Spectral.electricBlue
        case .paused:
            LiquidDesignTokens.Surface.onSurface
        default:
            LiquidDesignTokens.Surface.onSurface
        }
    }

    // MARK: - Helpers

    /// Behavioral ring subtitle per spec §11: Ready, Protecting, Check, Return.
    /// Escalates to "Check" during active focus when guardian has surfaced a challenge.
    private var stateLabel: String {
        switch timerVM.state {
        case .idle:
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
        case .idle: return LiquidDesignTokens.Surface.onSurfaceMuted
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

    private func openStatsWindow(requestedTab: CompanionTab?) {
        if let requestedTab {
            UserDefaults.standard.set(requestedTab.rawValue, forKey: "companionRequestedTab")
        }
        // Close popover first so performClose cannot target the newly opened companion window.
        timerVM.closePopover()
        DispatchQueue.main.async {
            openWindow(id: "stats")
            timerVM.requestAppActivation?()
        }
    }
}

// MARK: - Idle State

private struct IdlePopoverContent: View {
    @Binding var selectedProject: Project?
    @Binding var selectedMinutes: Int
    let coachEnabled: Bool
    @Binding var coachTaskType: FocusCoachTaskType
    @Binding var coachResistance: Int
    let recoveryState: CrashRecoveryState?
    let recoveryProject: Project?
    let onStartFocus: () -> Void
    let onResumeRecovery: () -> Void
    let onDiscardRecovery: () -> Void

    @State private var showCustomSlider: Bool = false
    @State private var startCommitting: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let presetMinutes: [Int] = [5, 15, 25, 45]

    var body: some View {
        VStack(spacing: 0) {
            // Crash recovery banner — highest priority
            if let recovery = recoveryState {
                recoveryBanner(recovery)
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            // Coach pre-session intention card
            if coachEnabled && selectedProject == nil {
                FocusCoachPreSessionCard(
                    selectedTaskType: $coachTaskType,
                    resistanceLevel: $coachResistance
                )
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 12)
            }

            // PROJECT label
            HStack {
                TrackedLabel(
                    text: "Project",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.8
                )
                Spacer()
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            .padding(.top, 16)

            ProjectPickerView(selectedProject: $selectedProject)
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 6)

            durationPillSelector
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 14)

            Text("Guardian watches for browsing, off-project coding, low-priority work, and long drift.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            startButton
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
    }

    private var durationPillSelector: some View {
        VStack(spacing: 8) {
            HStack {
                TrackedLabel(
                    text: "Duration",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.8
                )
                Spacer()
                Text("\(selectedMinutes) min")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            durationPillRow

            if showCustomSlider {
                customSlider
                    .transition(.opacity)
            }
        }
    }

    private var durationPillRow: some View {
        DurationPresetRow(
            presets: Self.presetMinutes,
            selectedMinutes: $selectedMinutes,
            showCustom: true,
            isCustomActive: $showCustomSlider
        )
    }

    private var customSlider: some View {
        Slider(value: Binding(
            get: { Double(selectedMinutes) },
            set: { selectedMinutes = Int($0) }
        ), in: 5...120, step: 1)
        .tint(LiquidDesignTokens.Spectral.primaryContainer)
        .accessibilityLabel("Focus duration")
        .accessibilityValue("\(selectedMinutes) minutes")
    }

    private var startButton: some View {
        GradientCTAButton(
            title: "Start Focus Session",
            icon: "play.fill",
            gradient: LiquidDesignTokens.Gradient.focus,
            action: {
                if !reduceMotion {
                    withAnimation(FFMotion.commit) { startCommitting = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onStartFocus()
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
        let projectName = recoveryProject?.name ?? recovery.customLabel ?? "Focus"
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

// MARK: - Focusing State

private struct FocusingPopoverContent: View {
    @Binding var showStopConfirmation: Bool
    @Binding var selectedProject: Project?
    let projectName: String?
    let canReduceTime: Bool
    let canExtendTime: Bool
    let showPauseReasonChips: Bool
    let cycleProgress: Double
    let onPause: () -> Void
    let onExtendTime: () -> Void
    let onReduceTime: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void
    let onPauseReasonSelected: (FocusCoachReason) -> Void
    let onPauseReasonDismissed: () -> Void
    let onSwitchProject: (Project?, FocusCoachReason) -> Void

    @State private var saveAnimating = false
    @State private var discardAnimating = false
    @State private var showProjectSwitcher = false
    @State private var switchTarget: Project?
    @State private var showSwitchReasonChips = false

    var body: some View {
        VStack(spacing: 12) {
            // Inline pause reason chips (shown after resuming from 2+ min pause)
            if showPauseReasonChips {
                pauseReasonChipStrip
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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

            // -5/+5 min Extension buttons
            extensionButtons
                .padding(.top, 8)

            // Switch project inline flow
            if showProjectSwitcher {
                projectSwitcherInline
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else if showSwitchReasonChips {
                switchReasonChipStrip
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

            nextUpCard
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private var extensionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onReduceTime) {
                HStack(spacing: 4) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("5 min")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 44)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(!canReduceTime)
            .opacity(canReduceTime ? 1 : 0.38)
            .accessibilityLabel("Reduce time by 5 minutes")
            .help(canReduceTime ? "Reduce session by 5 minutes" : "Less than 6 minutes remaining")

            Button(action: onExtendTime) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("5 min")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 44)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(!canExtendTime)
            .opacity(canExtendTime ? 1 : 0.38)
            .accessibilityLabel("Extend time by 5 minutes")
            .help(canExtendTime ? "Extend session by 5 minutes" : "Maximum session length (4 hours) reached")
        }
    }

    private var pauseReasonChipStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Long pause — what happened?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                Spacer()
                Button {
                    withAnimation(FFMotion.section) { onPauseReasonDismissed() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss pause reason")
            }

            FlowLayout(spacing: 6) {
                ForEach(FocusCoachReason.allCases, id: \.self) { reason in
                    Button {
                        withAnimation(FFMotion.section) { onPauseReasonSelected(reason) }
                    } label: {
                        Text(reason.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel(reason.displayName)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .strokeBorder(Color.orange.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.top, 6)
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
                        .font(.system(size: 9, weight: .semibold))
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
                        showSwitchReasonChips = true
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

    private var switchReasonChipStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why switching?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

            let switchReasons: [FocusCoachReason] = [.requiredSwitch, .meeting, .familyPersonal, .procrastinating]
            FlowLayout(spacing: 6) {
                ForEach(switchReasons, id: \.self) { reason in
                    Button {
                        withAnimation(FFMotion.section) {
                            showSwitchReasonChips = false
                            onSwitchProject(switchTarget, reason)
                        }
                    } label: {
                        Text(reason.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel(reason.displayName)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.06))
                .strokeBorder(Color.blue.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var nextUpCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.purple.opacity(0.7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                TrackedLabel(
                    text: "Next Up",
                    font: .system(size: 10, weight: .medium),
                    tracking: 2.0
                )
                Text(projectName ?? "Break Time")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
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
    let overtimeString: String
    let showSessionComplete: Bool
    let cycleProgress: Double
    let onBringWindowToFront: () -> Void
    let onTakeBreak: () -> Void
    let onSkipBreak: () -> Void
    let onFinishSession: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Overtime badge
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x3DA86A))
                    .accessibilityHidden(true)
                Text(overtimeString)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x3DA86A))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(hex: 0x3DA86A).opacity(0.12))
            )

            if showSessionComplete {
                // Session window is open — guide user there instead of offering bypass actions
                VStack(spacing: 10) {
                    Text("Your session is complete ✓")
                        .font(LiquidDesignTokens.Typography.bodySmall)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

                    Button(action: onBringWindowToFront) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                                .accessibilityHidden(true)
                            Text("Log & Continue →")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                }
            } else {
                // Window not open — inline quick actions (e.g. if window was dismissed)
                GlassEffectContainer {
                    VStack(spacing: 8) {
                        // Primary CTA — coached path (full width, no truncation)
                        GradientCTAButton(
                            title: "Take a Break",
                            icon: "cup.and.saucer.fill",
                            gradient: LiquidDesignTokens.Gradient.breakStart,
                            action: onTakeBreak
                        )

                        // Secondary actions row — lower visual weight
                        HStack(spacing: 8) {
                            Button(action: onSkipBreak) {
                                HStack(spacing: 5) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 10))
                                        .accessibilityHidden(true)
                                    Text("Start Next Block")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)

                            Button(action: onFinishSession) {
                                HStack(spacing: 5) {
                                    Image(systemName: cycleProgress >= 1.0 ? "checkmark.seal.fill" : "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .accessibilityHidden(true)
                                    Text(cycleProgress >= 1.0 ? "Complete Block" : "End with Progress")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }
            }

            // Next session project picker (only when window not blocking actions)
            if !showSessionComplete {
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
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }
}

// MARK: - Break Overtime State

private struct BreakOvertimePopoverContent: View {
    let overtimeString: String
    let onStartFocusing: () -> Void
    let onEnd: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            // Escalating overtime badge — orange to signal urgency
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(overtimeString)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Color.orange.opacity(pulse ? 0.2 : 0.12)))
            .opacity(pulse ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            Text("Break time is up — time to focus!")
                .font(LiquidDesignTokens.Typography.bodySmall)
                .foregroundStyle(.orange.opacity(0.85))
                .italic()

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
                    }
                    .buttonStyle(.plain)
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
    let onSkipBreak: () -> Void

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

            // Skip Break — native glass button
            Button(action: onSkipBreak) {
                HStack(spacing: 6) {
                    Text("Start Next Block")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - MenuBarPopoverView State Wiring

extension MenuBarPopoverView {
    fileprivate var idleContent: some View {
        @Bindable var vm = timerVM
        return IdlePopoverContent(
            selectedProject: $vm.selectedProject,
            selectedMinutes: $vm.selectedMinutes,
            coachEnabled: timerVM.settings?.coachRealtimeEnabled ?? false,
            coachTaskType: Binding(
                get: { timerVM.coachTaskType },
                set: { timerVM.coachTaskType = $0 }
            ),
            coachResistance: Binding(
                get: { timerVM.coachResistance },
                set: { timerVM.coachResistance = $0 }
            ),
            recoveryState: timerVM.recoveryState,
            recoveryProject: timerVM.recoveryProject,
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
        .onChange(of: timerVM.selectedProject) { _, newValue in
            if newValue != nil { timerVM.noteProjectSelected() }
        }
    }

    fileprivate var focusingContent: some View {
        @Bindable var vm = timerVM
        return FocusingPopoverContent(
            showStopConfirmation: $showStopConfirmation,
            selectedProject: $vm.selectedProject,
            projectName: timerVM.selectedProject?.name,
            canReduceTime: timerVM.canReduceTime,
            canExtendTime: timerVM.canExtendTime,
            showPauseReasonChips: timerVM.showPauseReasonChips,
            cycleProgress: timerVM.cycleProgress,
            onPause: { timerVM.pause() },
            onExtendTime: {
                timerVM.extendTimer()
            },
            onReduceTime: {
                timerVM.extendTimer(by: -300)
            },
            onShowStopConfirmation: {
                withAnimation { showStopConfirmation = true }
            },
            onSaveStop: { timerVM.stopForReflection() },
            onDiscardStop: { timerVM.abandonSession() },
            onCancelStop: { showStopConfirmation = false },
            onPauseReasonSelected: { reason in timerVM.recordPauseReason(reason) },
            onPauseReasonDismissed: { timerVM.dismissPauseReasonChips() },
            onSwitchProject: { project, reason in timerVM.switchProject(to: project, reason: reason) }
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
            onSkipBreak: { timerVM.skipBreak() }
        )
    }

    fileprivate var breakOvertimeContent: some View {
        BreakOvertimePopoverContent(
            overtimeString: timerVM.overtimeTimeString,
            onStartFocusing: {
                timerVM.continueAfterCompletion(action: .continueFocusing)
            },
            onEnd: {
                timerVM.continueAfterCompletion(action: .endSession)
            }
        )
    }

    fileprivate var overtimeContent: some View {
        @Bindable var vm = timerVM
        return OvertimePopoverContent(
            selectedProject: $vm.selectedProject,
            overtimeString: timerVM.overtimeTimeString,
            showSessionComplete: timerVM.showSessionComplete,
            cycleProgress: timerVM.cycleProgress,
            onBringWindowToFront: {
                timerVM.openCompletionWindow?()
                timerVM.requestAppActivation?()
            },
            onTakeBreak: {
                timerVM.continueAfterCompletion(action: .takeBreak(duration: nil))
            },
            onSkipBreak: {
                timerVM.continueAfterCompletion(action: .continueFocusing)
            },
            onFinishSession: {
                timerVM.continueAfterCompletion(action: .endSession)
            }
        )
    }
}
