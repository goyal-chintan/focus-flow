import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @State private var showStopConfirmation = false

    @State private var didConfigure = false
    @State private var hasAnimatedEntry = false
    @State private var motionTick = 0
    @State private var didAutoOpenLab = false

    var body: some View {
        content
            .task(id: didConfigure) {
                if !didConfigure {
                    didConfigure = true
                    timerVM.ensureConfigured(modelContext: modelContext)
                }
            }
            .onAppear {
                guard !hasAnimatedEntry else { return }
                withAnimation(tokens.motion.popover) {
                    hasAnimatedEntry = true
                }

                if !didAutoOpenLab {
                    didAutoOpenLab = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        openWindow(id: "variant-lab")
                    }
                }
            }
            .onDisappear {
                hasAnimatedEntry = false
            }
            .onChange(of: timerVM.state) { _, _ in
                withAnimation(tokens.motion.section) {
                    motionTick += 1
                    showStopConfirmation = false
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        mainContent
            .onChange(of: timerVM.showSessionComplete) { _, newValue in
                if newValue {
                    openWindow(id: "session-complete")
                }
            }
    }

    private var mainContent: some View {
        @Bindable var timerVM = timerVM

        return VStack(spacing: tokens.spacing.lg) {
            // Timer ring floats freely — no card wrapper
            heroSection

            if timerVM.state == .idle {
                idleSection
            } else {
                liveStatusStrip
            }

            // Action buttons directly — no card wrapper
            GlassEffectContainer {
                controlsSection
            }
            .animation(tokens.motion.section, value: controlsIdentity)

            variantLabLaunchSection

            footerSection
        }
        .padding(tokens.spacing.lg)
        .frame(width: tokens.layout.popoverWidth)
        .background(
            RoundedRectangle(cornerRadius: tokens.radius.hero, style: .continuous)
                .fill(.thickMaterial.opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: tokens.radius.hero, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16))
                }
                .overlay {
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), Color.clear, Color.white.opacity(0.015)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: tokens.radius.hero, style: .continuous))
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: tokens.radius.hero, style: .continuous))
        .opacity(hasAnimatedEntry ? 1 : 0)
        .offset(y: hasAnimatedEntry ? 0 : -8)
        .scaleEffect(hasAnimatedEntry ? 1 : 0.97, anchor: .top)
        .animation(tokens.motion.section, value: timerVM.state)
        .animation(tokens.motion.popover, value: hasAnimatedEntry)
    }

    // MARK: - Hero (no wrapper — ring floats on popover glass)

    private var heroSection: some View {
        VStack(spacing: tokens.spacing.xs) {
            TimerRingView(
                progress: timerVM.progress,
                timeString: timerVM.state == .idle ? defaultTimeString : timerVM.timeString,
                label: stateLabel,
                state: timerVM.state
            )

            SessionDotsView(
                completed: timerVM.completedFocusSessions % timerVM.sessionsBeforeLongBreak,
                total: timerVM.sessionsBeforeLongBreak
            )
            .opacity(timerVM.state == .idle && timerVM.completedFocusSessions == 0 ? 0.5 : 1)
        }
        .frame(maxWidth: .infinity)
        .id("hero-\(stateKey)")
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    // MARK: - Idle (no wrapper — controls float directly)

    private var idleSection: some View {
        @Bindable var timerVM = timerVM

        return VStack(spacing: tokens.spacing.sm) {
            ProjectPickerView(
                selectedProject: $timerVM.selectedProject
            )

            GlassEffectContainer {
                durationPresetButtons
            }

            customDurationStepper
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
            removal: .opacity
        ))
    }

    private var durationPresetButtons: some View {
        HStack(spacing: tokens.spacing.xs) {
            durationButton(mins: 15)
            durationButton(mins: 25)
            durationButton(mins: 45)
            durationButton(mins: 60)
        }
    }

    @ViewBuilder
    private func durationButton(mins: Int) -> some View {
        let isSelected = timerVM.selectedMinutes == mins

        if isSelected {
            Button { timerVM.selectedMinutes = mins } label: {
                Text("\(mins)m")
                    .font(tokens.typography.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, tokens.spacing.sm)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.white.opacity(0.64))
            .animation(tokens.motion.control, value: timerVM.selectedMinutes)
        } else {
            Button { timerVM.selectedMinutes = mins } label: {
                Text("\(mins)m")
                    .font(tokens.typography.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, tokens.spacing.sm)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.white.opacity(0.5))
            .animation(tokens.motion.control, value: timerVM.selectedMinutes)
        }
    }

    private var customDurationStepper: some View {
        @Bindable var timerVM = timerVM

        return HStack(spacing: tokens.spacing.sm) {
            Button {
                if timerVM.selectedMinutes > 5 { timerVM.selectedMinutes -= 5 }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.white.opacity(0.44))

            Text("\(timerVM.selectedMinutes) min")
                .font(tokens.typography.title)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            Button {
                if timerVM.selectedMinutes < 120 { timerVM.selectedMinutes += 5 }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.white.opacity(0.44))
        }
    }

    private var customDurationInput: some View {
        @Bindable var timerVM = timerVM

        return HStack(spacing: tokens.spacing.sm) {
            Text("Custom")
                .font(tokens.typography.meta)
                .foregroundStyle(.secondary)

            Spacer()

            TextField("Minutes", value: $timerVM.selectedMinutes, format: .number)
                .textFieldStyle(.plain)
                .font(tokens.typography.bodyFont)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .padding(.horizontal, tokens.spacing.sm)
                .padding(.vertical, tokens.spacing.xs)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: tokens.radius.control, style: .continuous))

            Text("min")
                .font(tokens.typography.meta)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Live Status

    private var liveStatusStrip: some View {
        HStack(spacing: tokens.spacing.sm) {
            if timerVM.state == .paused {
                statusChip("Paused \(timerVM.pauseTimeString)", color: timerVM.pauseWarningLevel.color)
            } else if timerVM.isBlockingActive {
                statusChip("Blocking", color: .green)
            }

            switch timerVM.state {
            case .focusing:
                statusChip(timerVM.selectedProject?.name ?? "Focus", color: .secondary)
            case .onBreak(let type):
                statusChip(type.displayName, color: tokens.color.success)
            default:
                EmptyView()
            }

            Spacer(minLength: 0)
        }
        .id("live-\(stateKey)-\(motionTick)")
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity
        ))
    }

    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(tokens.typography.meta)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, tokens.spacing.sm)
            .padding(.vertical, tokens.spacing.xs)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.08))
            }
            .contentTransition(.interpolate)
            .animation(tokens.motion.control, value: text)
    }

    // MARK: - Controls (inside GlassEffectContainer, no PremiumSurface)

    @ViewBuilder
    private var controlsSection: some View {
        switch timerVM.state {
        case .idle:
            ControlButton(title: "Start Focus", icon: "play.fill", role: .primary) {
                NSLog("FocusFlow: START FOCUS CLICKED")
                timerVM.ensureConfigured(modelContext: modelContext)
                timerVM.startFocus()
            }

        case .focusing:
            VStack(spacing: tokens.spacing.sm) {
                HStack(spacing: tokens.spacing.xs) {
                    ControlButton(title: "Pause", icon: "pause.fill", role: .secondary) {
                        timerVM.pause()
                    }
                    ControlButton(title: "Stop", icon: "stop.fill", role: .destructive) {
                        withAnimation { showStopConfirmation = true }
                    }
                }

                if showStopConfirmation {
                    stopConfirmationView
                }
            }

        case .paused:
            VStack(spacing: tokens.spacing.sm) {
                VStack(spacing: tokens.spacing.xxs) {
                    Text("Paused for")
                        .font(tokens.typography.meta)
                        .foregroundStyle(.secondary)
                    Text(timerVM.pauseTimeString)
                        .font(tokens.typography.titleLarge)
                        .monospacedDigit()
                        .foregroundStyle(timerVM.pauseWarningLevel.color)
                        .contentTransition(.numericText())
                        .animation(tokens.motion.control, value: timerVM.pauseTimeString)
                }

                HStack(spacing: tokens.spacing.xs) {
                    ControlButton(title: "Resume", icon: "play.fill", role: .primary) {
                        timerVM.resume()
                    }
                    ControlButton(title: "Stop", icon: "stop.fill", role: .destructive) {
                        withAnimation { showStopConfirmation = true }
                    }
                }

                if showStopConfirmation {
                    stopConfirmationView
                }
            }

        case .onBreak:
            ControlButton(title: "Skip Break", icon: "forward.fill", role: .secondary) {
                timerVM.skipBreak()
            }
        }
    }

    // MARK: - Footer

    private var variantLabLaunchSection: some View {
        HStack(spacing: tokens.spacing.xs) {
            Button {
                openWindow(id: "variant-lab")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: tokens.spacing.xs) {
                    Image(systemName: "square.grid.3x3.fill")
                    Text("Variant Lab")
                        .font(tokens.typography.callout)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, tokens.spacing.md)
                .padding(.vertical, tokens.spacing.sm)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: tokens.radius.control))
            .tint(tokens.color.focus.opacity(0.9))

            Button {
                openWindow(id: "design-lab")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: tokens.spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Design Lab (Advanced)")
                        .font(tokens.typography.callout)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, tokens.spacing.md)
                .padding(.vertical, tokens.spacing.sm)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: tokens.radius.control))
            .tint(.white.opacity(0.5))
        }
    }

    private var footerSection: some View {
        HStack(spacing: tokens.spacing.sm) {
            Label {
                Text(footerText)
                    .font(tokens.typography.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
            } icon: {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: tokens.spacing.xs)

            HStack(spacing: tokens.spacing.xs) {
                Button {
                    openWindow(id: "variant-lab")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("Lab", systemImage: "square.grid.3x3.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(tokens.color.focus.opacity(0.85))

                Button {
                    openWindow(id: "stats")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("Stats", systemImage: "chart.bar.fill")
                        .font(tokens.typography.meta)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.white.opacity(0.5))
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .padding(.top, tokens.spacing.xs)
        .animation(tokens.motion.control, value: footerText)
    }

    // MARK: - Stop Confirmation (no PremiumSurface wrapper)

    private var stopConfirmationView: some View {
        VStack(spacing: tokens.spacing.sm) {
            Text("End this session?")
                .font(tokens.typography.callout)

            GlassEffectContainer {
                HStack(spacing: tokens.spacing.xs) {
                    Button {
                        timerVM.stop()
                        showStopConfirmation = false
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(tokens.typography.meta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, tokens.spacing.sm)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.5))

                    Button {
                        timerVM.abandonSession()
                        showStopConfirmation = false
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(tokens.typography.meta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, tokens.spacing.sm)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(tokens.color.danger)

                    Button {
                        showStopConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(tokens.typography.meta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, tokens.spacing.sm)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.5))
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Computed

    private var stateLabel: String {
        switch timerVM.state {
        case .idle: "Ready to Focus"
        case .focusing: timerVM.sessionLabel
        case .paused: "Paused"
        case .onBreak(let type): type.displayName
        }
    }

    private var defaultTimeString: String {
        let mins = max(5, timerVM.selectedMinutes)
        return String(format: "%02d:00", mins)
    }

    private var footerText: String {
        let sessions = timerVM.todaySessionCount
        let time = timerVM.todayFocusTime.formattedFocusTime
        if sessions == 0 { return "No sessions yet today" }
        return "\(sessions) session\(sessions == 1 ? "" : "s") \u{00B7} \(time) focused"
    }

    private var stateKey: String {
        switch timerVM.state {
        case .idle: "idle"
        case .focusing: "focusing"
        case .paused: "paused"
        case .onBreak(let type): "break-\(type.rawValue)"
        }
    }

    private var controlsIdentity: String {
        "\(stateKey)-\(showStopConfirmation)"
    }
}
