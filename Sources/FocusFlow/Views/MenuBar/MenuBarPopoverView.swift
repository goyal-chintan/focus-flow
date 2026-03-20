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
                Text("FocusFlow")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

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
            state: timerVM.state
        )
        .padding(.top, timerVM.state == .idle ? 18 : 10)
        .padding(.bottom, timerVM.state == .idle ? 6 : 2)
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
                    .frame(width: 28, height: 28)
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
                text: "Today's Total",
                font: LiquidDesignTokens.Typography.labelSmall,
                tracking: 1.0
            )
        default:
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                Text("Today's Total")
                    .font(LiquidDesignTokens.Typography.labelLarge)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.88))
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

    let onStartFocus: () -> Void

    private let presets = [15, 25, 45, 60]

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

            presetsRow
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 14)

            if showCustomInput {
                customInput
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            startButton
                .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
    }

    private var presetsRow: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { mins in
                presetButton(mins)
            }
            customButton
        }
    }

    @ViewBuilder
    private func presetButton(_ mins: Int) -> some View {
        let isSelected = selectedMinutes == mins && !showCustomInput
        Button {
            withAnimation(FFMotion.control) {
                showCustomInput = false
                selectedMinutes = mins
            }
        } label: {
            Text("\(mins)")
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .if(isSelected) { view in
            view.buttonStyle(.glassProminent)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
        }
        .if(!isSelected) { view in
            view.buttonStyle(.glass)
        }
        .buttonBorderShape(.capsule)
    }

    private var customButton: some View {
        let isSelected = showCustomInput
        return Button {
            withAnimation(FFMotion.control) {
                showCustomInput.toggle()
            }
        } label: {
            Text("CUST")
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .italic()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .if(isSelected) { view in
            view.buttonStyle(.glassProminent)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
        }
        .if(!isSelected) { view in
            view.buttonStyle(.glass)
        }
        .buttonBorderShape(.capsule)
    }

    private var customInput: some View {
        HStack(spacing: 8) {
            TextField("Min", value: $selectedMinutes, format: .number)
                .textFieldStyle(.plain)
                .font(LiquidDesignTokens.Typography.bodyMedium)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                .frame(width: 50)
                .onChange(of: selectedMinutes) { _, newValue in
                    selectedMinutes = max(5, min(180, newValue))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.36))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                        )
                )

            Text("minutes")
                .font(LiquidDesignTokens.Typography.labelMedium)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
        }
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
    let onPause: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void

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
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .tint(LiquidDesignTokens.Spectral.salmon)
                .buttonBorderShape(.capsule)
            }
            .padding(.top, 14)

            if showStopConfirmation {
                stopConfirmation
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
        .padding(.bottom, 12)
    }

    private var stopConfirmation: some View {
        VStack(spacing: 8) {
            Text("End this session?")
                .font(LiquidDesignTokens.Typography.labelLarge)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

            HStack(spacing: 8) {
                Button(action: onSaveStop) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 10))

                Button(action: onDiscardStop) {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glass)
                .tint(LiquidDesignTokens.Spectral.destructive)
                .buttonBorderShape(.roundedRectangle(radius: 10))

                Button("Cancel", action: onCancelStop)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.roundedRectangle(radius: 10))
            }
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

    var body: some View {
        VStack(spacing: 14) {
            // Pause info
            VStack(spacing: 4) {
                Text("Paused for \(pauseTimeString)")
                    .font(LiquidDesignTokens.Typography.headlineLarge)
                    .foregroundStyle(LiquidDesignTokens.Spectral.amber)

                Text("Deep work momentum is fading...")
                    .font(LiquidDesignTokens.Typography.bodySmall)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .italic()
            }
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
                .foregroundStyle(Color(hex: 0x1A1200))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xD4940A),
                                Color(hex: 0xFFC07A),
                                Color(hex: 0xFFD89E)
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
            .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)

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
                    .padding(.horizontal, LiquidDesignTokens.Padding.popoverHorizontal)
            }
        }
        .padding(.bottom, 12)
    }

    private var pausedStopConfirmation: some View {
        HStack(spacing: 8) {
            Button("Save & End", action: onSaveStop)
                .frame(maxWidth: .infinity, minHeight: 30)
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 10))

            Button("Discard", action: onDiscardStop)
                .frame(maxWidth: .infinity, minHeight: 30)
                .buttonStyle(.glass)
                .tint(LiquidDesignTokens.Spectral.destructive)
                .buttonBorderShape(.roundedRectangle(radius: 10))

            Button("Cancel", action: onCancelStop)
                .frame(maxWidth: .infinity, minHeight: 30)
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 10))
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
