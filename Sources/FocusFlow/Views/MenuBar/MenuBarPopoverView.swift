import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @State private var showStopConfirmation = false
    @State private var didConfigure = false

    var body: some View {
        popoverShell
            .task(id: didConfigure) {
                if !didConfigure {
                    didConfigure = true
                    timerVM.ensureConfigured(modelContext: modelContext)
                }
            }
            .onChange(of: timerVM.showSessionComplete) { _, newValue in
                if newValue {
                    openWindow(id: "session-complete")
                }
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

                timerHeroSection

                stateSection

                if let error = timerVM.startError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                            Color(hex: 0x0C1322).opacity(0.1),
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
        .animation(FFMotion.section, value: timerVM.state)
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
                    openWindow(id: "stats")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open statistics")

                Button {
                    NSApp.sendAction(#selector(NSPopover.performClose(_:)), to: nil, from: nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(width: 30, height: 30)
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
                    text: "Overtime",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    color: Color(hex: 0x3DA86A),
                    tracking: 1.8
                )
                Text(timerVM.selectedProject?.name ?? "Focus")
                    .font(LiquidDesignTokens.Typography.headlineMedium)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .lineLimit(1)
            }
            .padding(.top, 12)
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
            pauseDuration: timerVM.pauseElapsed,
            pauseTimeString: timerVM.pauseTimeString
        )
        .padding(.top, (timerVM.state == .idle && !timerVM.isOvertime) ? 20 : 10)
        .padding(.bottom, (timerVM.state == .idle && !timerVM.isOvertime) ? 8 : 4)
    }

    // MARK: - State Section

    @ViewBuilder
    private var stateSection: some View {
        if timerVM.isOvertime {
            overtimeContent
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
                    openWindow(id: "stats")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
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

    private var stateLabel: String {
        if timerVM.isOvertime { return "Overtime" }
        switch timerVM.state {
        case .idle:
            return "Focus Session"
        case .focusing:
            return "Remaining"
        case .paused:
            return "Focus Paused"
        case .onBreak(let type):
            return type.displayName
        }
    }

    private var defaultTimeString: String {
        let mins = max(5, timerVM.selectedMinutes)
        return String(format: "%02d:00", mins)
    }
}

// MARK: - Idle State

private struct IdlePopoverContent: View {
    @Binding var selectedProject: Project?
    @Binding var selectedMinutes: Int
    @Binding var blockUntilGoalMet: Bool

    let onStartFocus: () -> Void

    @State private var showCustomSlider: Bool = false

    private static let presetMinutes: [Int] = [5, 15, 25, 45]

    var body: some View {
        VStack(spacing: 0) {
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

            // Block until goal toggle
            if selectedProject?.blockProfile != nil {
                HStack(spacing: 8) {
                    Image(systemName: blockUntilGoalMet ? "shield.checkered" : "shield")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(blockUntilGoalMet ? .green : .secondary)

                    Text("Block until daily goal met")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Toggle("", isOn: $blockUntilGoalMet)
                        .toggleStyle(.switch)
                        .scaleEffect(0.75)
                        .frame(width: 40)
                        .accessibilityLabel("Block until daily goal met")
                }
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 8)
            }

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
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
            action: onStartFocus
        )
    }

}

// MARK: - Focusing State

private struct FocusingPopoverContent: View {
    @Binding var showStopConfirmation: Bool
    let projectName: String?
    let onPause: () -> Void
    let onExtendTime: () -> Void
    let onReduceTime: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void

    @State private var saveAnimating = false
    @State private var discardAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            // Pause / Stop buttons — native glass
            HStack(spacing: 8) {
                Button(action: onPause) {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Pause focus session")

                Button {
                    withAnimation(FFMotion.section) { onShowStopConfirmation() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                        Text("Stop")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Stop focus session")
            }
            .padding(.top, 14)

            // -5/+5 min Extension buttons
            extensionButtons

            if showStopConfirmation {
                stopConfirmation
            }

            nextUpCard
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private var extensionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onReduceTime) {
                HStack(spacing: 4) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("5 min")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Reduce time by 5 minutes")

            Button(action: onExtendTime) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("5 min")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Extend time by 5 minutes")
        }
    }

    private var nextUpCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.purple.opacity(0.7))

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

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    saveAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSaveStop()
                }
            } label: {
                Label("Save & End", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
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
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .scaleEffect(discardAnimating ? 0.92 : 1.0)
            .opacity(discardAnimating ? 0.5 : 1.0)

            Button {
                withAnimation(FFMotion.control) { onCancelStop() }
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
        .padding(12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Paused State

private struct PausedPopoverContent: View {
    let pauseTimeString: String
    let pauseWarningColor: Color
    @Binding var showStopConfirmation: Bool
    let onResume: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void

    @State private var saveAnimating = false
    @State private var discardAnimating = false

    var body: some View {
        VStack(spacing: 14) {
            // Motivational nudge — pause time is now shown in the ring
            Text("Deep work momentum is fading...")
                .font(LiquidDesignTokens.Typography.bodySmall)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .italic()
                .padding(.top, 8)

            // Resume CTA — amber gradient
            GradientCTAButton(
                title: "Resume Focus",
                icon: "play.fill",
                gradient: LiquidDesignTokens.Gradient.resume,
                foregroundColor: Color(hex: 0x332200),
                action: onResume
            )

            // End Session — native glass button
            Button {
                withAnimation(FFMotion.section) { onShowStopConfirmation() }
            } label: {
                TrackedLabel(
                    text: "End Session",
                    font: LiquidDesignTokens.Typography.labelMedium,
                    color: LiquidDesignTokens.Surface.onSurfaceMuted,
                    tracking: 2.0
                )
            }
            .buttonStyle(.plain)

            if showStopConfirmation {
                pausedStopConfirmation
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private var pausedStopConfirmation: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    saveAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSaveStop()
                }
            } label: {
                Label("Save & End", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
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
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .scaleEffect(discardAnimating ? 0.92 : 1.0)
            .opacity(discardAnimating ? 0.5 : 1.0)

            Button {
                withAnimation(FFMotion.control) { onCancelStop() }
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Overtime State

private struct OvertimePopoverContent: View {
    @Binding var selectedProject: Project?
    let overtimeString: String
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

            // Action buttons
            GlassEffectContainer {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: onTakeBreak) {
                            HStack(spacing: 6) {
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 11))
                                Text("Take a Break")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(LiquidDesignTokens.Spectral.primaryContainer)
                        .buttonBorderShape(.capsule)

                        Button(action: onSkipBreak) {
                            HStack(spacing: 6) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 11))
                                Text("Skip Break")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    }

                    Button(action: onFinishSession) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text("Finish Session")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .tint(LiquidDesignTokens.Spectral.mint)
                    .buttonBorderShape(.capsule)
                }
            }

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
                    Text("Skip Break")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
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
            blockUntilGoalMet: $vm.blockUntilGoalMet,
            onStartFocus: {
                timerVM.ensureConfigured(modelContext: modelContext)
                timerVM.startFocus()
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    fileprivate var focusingContent: some View {
        FocusingPopoverContent(
            showStopConfirmation: $showStopConfirmation,
            projectName: timerVM.selectedProject?.name,
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
            onSaveStop: { timerVM.stop() },
            onDiscardStop: { timerVM.abandonSession() },
            onCancelStop: { showStopConfirmation = false }
        )
        .transition(.opacity)
    }

    fileprivate var pausedContent: some View {
        PausedPopoverContent(
            pauseTimeString: timerVM.pauseTimeString,
            pauseWarningColor: timerVM.pauseWarningLevel.color,
            showStopConfirmation: $showStopConfirmation,
            onResume: { timerVM.resume() },
            onShowStopConfirmation: {
                withAnimation { showStopConfirmation = true }
            },
            onSaveStop: { timerVM.stop() },
            onDiscardStop: { timerVM.abandonSession() },
            onCancelStop: { showStopConfirmation = false }
        )
        .transition(.opacity)
    }

    fileprivate var breakContent: some View {
        @Bindable var vm = timerVM
        return BreakPopoverContent(
            selectedProject: $vm.selectedProject,
            onSkipBreak: { timerVM.skipBreak() }
        )
        .transition(.opacity)
    }

    fileprivate var overtimeContent: some View {
        @Bindable var vm = timerVM
        return OvertimePopoverContent(
            selectedProject: $vm.selectedProject,
            overtimeString: timerVM.overtimeTimeString,
            onTakeBreak: {
                timerVM.continueAfterCompletion(action: .takeBreak)
            },
            onSkipBreak: {
                timerVM.continueAfterCompletion(action: .continueFocusing)
            },
            onFinishSession: {
                timerVM.continueAfterCompletion(action: .endSession)
            }
        )
        .transition(.opacity)
    }
}
