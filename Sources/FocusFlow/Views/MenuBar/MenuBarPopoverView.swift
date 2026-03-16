import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @State private var showStopConfirmation = false

    @State private var didConfigure = false
    @State private var hasAnimatedEntry = false
    @State private var motionTick = 0

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
                withAnimation(FFMotion.popover) {
                    hasAnimatedEntry = true
                }
            }
            .onDisappear {
                hasAnimatedEntry = false
            }
            .onChange(of: timerVM.state) { _, _ in
                withAnimation(FFMotion.section) {
                    motionTick += 1
                    showStopConfirmation = false
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if timerVM.showSessionComplete {
            SessionCompleteView()
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        @Bindable var timerVM = timerVM

        return VStack(spacing: FFSpacing.lg) {
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
            .animation(FFMotion.section, value: controlsIdentity)

            footerSection
        }
        .padding(FFSpacing.lg)
        .frame(width: 340)
        .opacity(hasAnimatedEntry ? 1 : 0)
        .offset(y: hasAnimatedEntry ? 0 : -8)
        .scaleEffect(hasAnimatedEntry ? 1 : 0.97, anchor: .top)
        .animation(FFMotion.section, value: timerVM.state)
        .animation(FFMotion.popover, value: hasAnimatedEntry)
    }

    // MARK: - Hero (no wrapper — ring floats on popover glass)

    private var heroSection: some View {
        VStack(spacing: FFSpacing.xs) {
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

        return VStack(spacing: FFSpacing.sm) {
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
        HStack(spacing: FFSpacing.xs) {
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
                    .font(FFType.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FFSpacing.sm)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(FFColor.focus)
            .animation(FFMotion.control, value: timerVM.selectedMinutes)
        } else {
            Button { timerVM.selectedMinutes = mins } label: {
                Text("\(mins)m")
                    .font(FFType.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FFSpacing.sm)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.white.opacity(0.5))
            .animation(FFMotion.control, value: timerVM.selectedMinutes)
        }
    }

    private var customDurationStepper: some View {
        @Bindable var timerVM = timerVM

        return HStack(spacing: FFSpacing.sm) {
            Button {
                if timerVM.selectedMinutes > 5 { timerVM.selectedMinutes -= 5 }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.white.opacity(0.5))

            Text("\(timerVM.selectedMinutes) min")
                .font(FFType.title)
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
            .tint(.white.opacity(0.5))
        }
    }

    private var customDurationInput: some View {
        @Bindable var timerVM = timerVM

        return HStack(spacing: FFSpacing.sm) {
            Text("Custom")
                .font(FFType.meta)
                .foregroundStyle(.secondary)

            Spacer()

            TextField("Minutes", value: $timerVM.selectedMinutes, format: .number)
                .textFieldStyle(.plain)
                .font(FFType.body)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .padding(.horizontal, FFSpacing.sm)
                .padding(.vertical, FFSpacing.xs)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous))

            Text("min")
                .font(FFType.meta)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Live Status

    private var liveStatusStrip: some View {
        HStack(spacing: FFSpacing.sm) {
            if timerVM.state == .paused {
                statusChip("Paused \(timerVM.pauseTimeString)", color: timerVM.pauseWarningLevel.color)
            } else if timerVM.isBlockingActive {
                statusChip("Blocking", color: .green)
            }

            switch timerVM.state {
            case .focusing:
                statusChip(timerVM.selectedProject?.name ?? "Focus", color: .secondary)
            case .onBreak(let type):
                statusChip(type.displayName, color: FFColor.success)
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
            .font(FFType.meta)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.08))
            }
            .contentTransition(.interpolate)
            .animation(FFMotion.control, value: text)
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
            VStack(spacing: FFSpacing.sm) {
                HStack(spacing: FFSpacing.xs) {
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
            VStack(spacing: FFSpacing.sm) {
                VStack(spacing: FFSpacing.xxs) {
                    Text("Paused for")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                    Text(timerVM.pauseTimeString)
                        .font(FFType.titleLarge)
                        .monospacedDigit()
                        .foregroundStyle(timerVM.pauseWarningLevel.color)
                        .contentTransition(.numericText())
                        .animation(FFMotion.control, value: timerVM.pauseTimeString)
                }

                HStack(spacing: FFSpacing.xs) {
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

    private var footerSection: some View {
        HStack(spacing: FFSpacing.sm) {
            Label {
                Text(footerText)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button {
                openWindow(id: "stats")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Stats", systemImage: "chart.bar.fill")
                    .font(FFType.meta)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.white.opacity(0.5))
        }
        .padding(.top, FFSpacing.xs)
        .animation(FFMotion.control, value: footerText)
    }

    // MARK: - Stop Confirmation (no PremiumSurface wrapper)

    private var stopConfirmationView: some View {
        VStack(spacing: FFSpacing.sm) {
            Text("End this session?")
                .font(FFType.callout)

            GlassEffectContainer {
                HStack(spacing: FFSpacing.xs) {
                    Button {
                        timerVM.stop()
                        showStopConfirmation = false
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(FFType.meta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.5))

                    Button {
                        timerVM.abandonSession()
                        showStopConfirmation = false
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(FFType.meta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FFColor.danger)

                    Button {
                        showStopConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(FFType.meta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
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
