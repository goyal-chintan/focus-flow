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
        .frame(width: 300)
        .background(.regularMaterial)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: timerVM.state)
    }

    // MARK: - Header Bar (focusing, paused, break only)

    @ViewBuilder
    private var headerBar: some View {
        switch timerVM.state {
        case .focusing, .paused, .onBreak:
            HStack {
                Text("FocusFlow")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        openWindow(id: "stats")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Close popover — sends dismiss action
                        NSApp.sendAction(#selector(NSPopover.performClose(_:)), to: nil, from: nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
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
                    text: "Active Context",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    color: LiquidDesignTokens.Spectral.electricBlue,
                    tracking: 1.5
                )
                Text("Project: \(timerVM.selectedProject?.name ?? "Focus")")
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
            state: timerVM.state
        )
        .padding(.top, timerVM.state == .idle ? 28 : 16)
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
        HStack(spacing: 6) {
            footerLeadingContent

            Spacer()

            Text(timerVM.todayFocusTime.formattedFocusTime)
                .font(LiquidDesignTokens.Typography.labelMedium)
                .foregroundStyle(footerTimeColor)
                .monospacedDigit()

            Button {
                openWindow(id: "stats")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
    }

    @ViewBuilder
    private var footerLeadingContent: some View {
        switch timerVM.state {
        case .focusing:
            TrackedLabel(
                text: "Today's Total",
                font: LiquidDesignTokens.Typography.labelSmall,
                tracking: 1.0
            )
        case .paused:
            HStack(spacing: 4) {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.amber)
                    .frame(width: 5, height: 5)
                TrackedLabel(
                    text: "Today's Total",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.0
                )
            }
        case .onBreak:
            TrackedLabel(
                text: "FocusFlow macOS",
                font: LiquidDesignTokens.Typography.labelSmall,
                tracking: 1.0
            )
        default:
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                Text("Today's Total")
                    .font(LiquidDesignTokens.Typography.labelSmall)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
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
    @State private var showCustomInput = false
    let isBlockingActive: Bool
    let blockingProfileName: String?
    let onStartFocus: () -> Void
    let onToggleBlocking: () -> Void

    private let presets = [15, 25, 45, 60]

    var body: some View {
        VStack(spacing: 0) {
            // PROJECT label
            HStack {
                TrackedLabel(
                    text: "Project",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )
                Spacer()
            }
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            .padding(.top, 16)

            ProjectPickerView(selectedProject: $selectedProject)
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 6)

            presetsRow
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 14)

            if showCustomInput {
                customInput
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            blockingProfileRow
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 14)

            startButton
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
    }

    private var presetsRow: some View {
        HStack(spacing: 2) {
            ForEach(presets, id: \.self) { mins in
                presetButton(mins)
            }

            // CUST button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showCustomInput.toggle()
                }
            } label: {
                Text("CUST")
                    .font(.system(size: 12, weight: showCustomInput ? .semibold : .regular))
                    .italic()
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(showCustomInput
                        ? LiquidDesignTokens.Spectral.electricBlue
                        : LiquidDesignTokens.Surface.onSurfaceMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
    }

    @ViewBuilder
    private func presetButton(_ mins: Int) -> some View {
        let isSelected = selectedMinutes == mins && !showCustomInput
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showCustomInput = false
                selectedMinutes = mins
            }
        } label: {
            Text("\(mins)")
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(isSelected
                    ? LiquidDesignTokens.Surface.onSurface
                    : LiquidDesignTokens.Surface.onSurfaceMuted)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customInput: some View {
        HStack(spacing: 8) {
            TextField("Min", value: $selectedMinutes, format: .number)
                .textFieldStyle(.plain)
                .font(LiquidDesignTokens.Typography.bodyMedium)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                .frame(width: 50)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LiquidDesignTokens.Surface.containerLow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(LiquidDesignTokens.Spectral.electricBlue.opacity(0.3), lineWidth: 1)
                        )
                )

            Text("minutes")
                .font(LiquidDesignTokens.Typography.labelMedium)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
        }
    }

    private var blockingProfileRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                TrackedLabel(
                    text: "Blocking Profile",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.2
                )
                Text(blockingProfileName ?? "None")
                    .font(LiquidDesignTokens.Typography.bodySmall)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: .constant(isBlockingActive))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        .opacity(blockingProfileName != nil ? 1 : 0.5)
    }

    private var startButton: some View {
        Button(action: onStartFocus) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                Text("Start Focus Session")
                    .font(LiquidDesignTokens.Typography.controlLabel)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.cta, style: .continuous)
                    .fill(ObsidianGradients.blueCTA())
                    .shadow(color: LiquidDesignTokens.Spectral.primaryContainer.opacity(0.3), radius: 16, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.cta, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Focusing State

private struct FocusingPopoverContent: View {
    @Binding var showStopConfirmation: Bool
    let onPause: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Pause / Stop buttons
            HStack(spacing: 8) {
                glassControlButton(title: "Pause", icon: "pause.fill", color: LiquidDesignTokens.Surface.onSurface) {
                    onPause()
                }
                glassControlButton(title: "Stop", icon: "stop.fill", color: LiquidDesignTokens.Spectral.salmon) {
                    withAnimation { onShowStopConfirmation() }
                }
            }
            .padding(.top, 14)

            if showStopConfirmation {
                stopConfirmation
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private func glassControlButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
        .buttonStyle(.plain)
    }

    private var stopConfirmation: some View {
        VStack(spacing: 8) {
            Text("End this session?")
                .font(LiquidDesignTokens.Typography.labelLarge)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

            HStack(spacing: 8) {
                obsidianTextButton("Save", icon: "square.and.arrow.down", action: onSaveStop)
                obsidianTextButton("Discard", icon: "trash", color: LiquidDesignTokens.Spectral.destructive, action: onDiscardStop)
                obsidianTextButton("Cancel", action: onCancelStop)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.card))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func obsidianTextButton(_ title: String, icon: String? = nil, color: Color = LiquidDesignTokens.Surface.onSurface, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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

    private var motivationText: String {
        // Basic motivation based on pause duration
        "Deep work momentum is fading..."
    }

    var body: some View {
        VStack(spacing: 14) {
            // Pause info
            VStack(spacing: 4) {
                Text("Paused for \(pauseTimeString)")
                    .font(LiquidDesignTokens.Typography.headlineLarge)
                    .foregroundStyle(LiquidDesignTokens.Spectral.amber)

                Text(motivationText)
                    .font(LiquidDesignTokens.Typography.bodySmall)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .italic()
            }
            .padding(.top, 8)

            // Resume CTA — uses blue gradient (consistent with Start Focus)
            Button(action: onResume) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("Resume Focus")
                        .font(LiquidDesignTokens.Typography.controlLabel)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.cta, style: .continuous)
                        .fill(ObsidianGradients.blueCTA())
                        .shadow(color: LiquidDesignTokens.Spectral.primaryContainer.opacity(0.3), radius: 16, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.cta, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)

            // End Session text link
            Button {
                withAnimation { onShowStopConfirmation() }
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
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            }
        }
        .padding(.bottom, 12)
    }

    private var pausedStopConfirmation: some View {
        HStack(spacing: 8) {
            Button(action: onSaveStop) {
                Text("Save & End")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: onDiscardStop) {
                Text("Discard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Spectral.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: onCancelStop) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
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

            // Skip Break button
            Button(action: onSkipBreak) {
                HStack(spacing: 6) {
                    Text("Skip Break")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(0.5)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                }
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
            }
            .buttonStyle(.plain)
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
            isBlockingActive: timerVM.isBlockingActive,
            blockingProfileName: timerVM.selectedProject?.blockProfile?.name,
            onStartFocus: {
                timerVM.ensureConfigured(modelContext: modelContext)
                timerVM.startFocus()
            },
            onToggleBlocking: {
                // Blocking activates automatically when focus starts
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    fileprivate var focusingContent: some View {
        FocusingPopoverContent(
            showStopConfirmation: $showStopConfirmation,
            onPause: { timerVM.pause() },
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
