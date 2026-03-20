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

    // MARK: - Header Bar (focusing, paused, break only)

    @ViewBuilder
    private var headerBar: some View {
        switch timerVM.state {
        case .focusing, .paused, .onBreak:
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
                }
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 4)
        default:
            EmptyView()
        }
    }

    // MARK: - Active Context (focusing only)

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
        }
    }

    // MARK: - Timer Hero (ring only, no dots)

    private var timerHeroSection: some View {
        TimerRingView(
            progress: timerVM.progress,
            timeString: timerVM.state == .idle ? defaultTimeString : timerVM.timeString,
            label: stateLabel,
            state: timerVM.state,
            isOvertime: timerVM.isOvertime,
            pauseDuration: timerVM.pauseElapsed,
            pauseTimeString: timerVM.pauseTimeString
        )
        .padding(.top, timerVM.state == .idle ? 20 : 10)
        .padding(.bottom, timerVM.state == .idle ? 8 : 4)
    }

    // MARK: - State Section

    @ViewBuilder
    private var stateSection: some View {
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
                Text("Today's Total")
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
        switch timerVM.state {
        case .idle:
            "Focus Session"
        case .focusing:
            "Remaining"
        case .paused:
            "Focus Paused"
        case .onBreak(let type):
            type.displayName
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

    let onStartFocus: () -> Void

    @State private var showCustomSlider: Bool = false

    private static let presetMinutes: [Int] = [15, 25, 30, 45]

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
        HStack(spacing: 6) {
            ForEach(Self.presetMinutes, id: \.self) { mins in
                durationPill(label: "\(mins)", isSelected: !showCustomSlider && selectedMinutes == mins) {
                    withAnimation(FFMotion.control) {
                        selectedMinutes = mins
                    }
                    withAnimation(FFMotion.section) {
                        showCustomSlider = false
                    }
                }
            }

            durationPill(label: "CUST", isSelected: showCustomSlider) {
                withAnimation(FFMotion.section) {
                    showCustomSlider = true
                }
            }
        }
    }

    private func durationPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonBorderShape(.capsule)
        .if(isSelected) { view in
            view.buttonStyle(.glassProminent)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
        }
        .if(!isSelected) { view in
            view.buttonStyle(.glass)
        }
    }

    private var customSlider: some View {
        Slider(value: Binding(
            get: { Double(selectedMinutes) },
            set: { selectedMinutes = Int($0) }
        ), in: 5...120, step: 1)
        .tint(LiquidDesignTokens.Spectral.primaryContainer)
    }

    private var startButton: some View {
        Button(action: onStartFocus) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Start Focus Session")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x5B9EF8),
                            Color(hex: 0x6AABFF),
                            Color(hex: 0xA5C4FF)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
    }

}

// MARK: - Focusing State

private struct FocusingPopoverContent: View {
    @Binding var showStopConfirmation: Bool
    let projectName: String?
    let onPause: () -> Void
    let onExtendTime: () -> Void
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
            }
            .padding(.top, 14)

            // +5m Extension button
            extensionButton

            if showStopConfirmation {
                stopConfirmation
            }

            nextUpCard
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private var extensionButton: some View {
        Button(action: onExtendTime) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("+5 Minutes")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
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

            // Resume CTA — blue gradient
            Button(action: onResume) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("RESUME FOCUS")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.0)
                }
                .foregroundStyle(Color(hex: 0x332200))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xCC8800),
                                Color(hex: 0xE6A820),
                                Color(hex: 0xF0C040)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
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

// MARK: - Break State

private struct BreakPopoverContent: View {
    let projectName: String?
    let onSkipBreak: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Next session context
            VStack(spacing: 3) {
                TrackedLabel(
                    text: "Next Session",
                    tracking: 2.0
                )
                if let projectName {
                    Text("Project: \(projectName)")
                        .font(LiquidDesignTokens.Typography.headlineMedium)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                }
            }
            .padding(.top, 8)

            // Skip Break — native glass button
            Button(action: onSkipBreak) {
                HStack(spacing: 6) {
                    Text("SKIP BREAK")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1.5)
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
        BreakPopoverContent(
            projectName: timerVM.selectedProject?.name,
            onSkipBreak: { timerVM.skipBreak() }
        )
        .transition(.opacity)
    }
}
