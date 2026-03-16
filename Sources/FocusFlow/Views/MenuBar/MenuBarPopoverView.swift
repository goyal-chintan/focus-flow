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
        mainContent
            .onChange(of: timerVM.showSessionComplete) { _, newValue in
                if newValue {
                    openWindow(id: "session-complete")
                }
            }
    }

    private var mainContent: some View {
        @Bindable var timerVM = timerVM

        return VStack(spacing: FFSpacing.md) {
            heroSection

            if timerVM.state == .idle {
                idleSection
            } else {
                liveStatusStrip
            }

            actionDeck

            footerSection
        }
        .padding(FFSpacing.md)
        .frame(width: 340)
        .opacity(hasAnimatedEntry ? 1 : 0)
        .offset(y: hasAnimatedEntry ? 0 : -8)
        .scaleEffect(hasAnimatedEntry ? 1 : 0.97, anchor: .top)
        .animation(FFMotion.section, value: timerVM.state)
        .animation(FFMotion.popover, value: hasAnimatedEntry)
    }

    private var heroSection: some View {
        PremiumSurface(style: .card, alignment: .center) {
            TimerRingView(
                progress: timerVM.progress,
                timeString: timerVM.state == .idle ? defaultTimeString : timerVM.timeString,
                label: stateLabel,
                state: timerVM.state
            )
            .frame(maxWidth: .infinity)

            SessionDotsView(
                completed: timerVM.completedFocusSessions % timerVM.sessionsBeforeLongBreak,
                total: timerVM.sessionsBeforeLongBreak
            )
            .opacity(timerVM.state == .idle && timerVM.completedFocusSessions == 0 ? 0.5 : 1)
            .frame(maxWidth: .infinity)
        }
        .id("hero-\(stateKey)")
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    private var idleSection: some View {
        @Bindable var timerVM = timerVM

        return PremiumSurface(style: .inset) {
            ProjectPickerView(
                selectedProject: $timerVM.selectedProject
            )

            durationPresetButtons

            customDurationInput
        }
        .id("idle-\(timerVM.selectedMinutes)")
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
        let label = Text("\(mins) min")
            .font(isSelected ? FFType.meta.weight(.semibold) : FFType.meta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.sm)

        if isSelected {
            Button { timerVM.selectedMinutes = mins } label: { label }
                .buttonStyle(.glassProminent)
                .tint(FFColor.focus)
                .contentTransition(.interpolate)
                .scaleEffect(1.0)
                .animation(FFMotion.control, value: timerVM.selectedMinutes)
        } else {
            Button { timerVM.selectedMinutes = mins } label: { label }
                .buttonStyle(.glass)
                .contentTransition(.interpolate)
                .animation(FFMotion.control, value: timerVM.selectedMinutes)
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
        .padding(.top, FFSpacing.xs)
    }

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
            VStack(spacing: 10) {
                HStack(spacing: 8) {
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
            VStack(spacing: 10) {
                // Pause duration display
                VStack(spacing: 4) {
                    Text("Paused for")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timerVM.pauseTimeString)
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timerVM.pauseWarningLevel.color)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: timerVM.pauseTimeString)
                }

                HStack(spacing: 8) {
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

    private var actionDeck: some View {
        PremiumSurface(style: .inset) {
            GlassEffectContainer {
                ZStack {
                    controlsSection
                }
                .id(controlsIdentity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
        .animation(FFMotion.section, value: controlsIdentity)
    }

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
            .buttonStyle(.glass)
        }
        .padding(.horizontal, FFSpacing.xs)
        .padding(.top, FFSpacing.xs)
        .animation(FFMotion.control, value: footerText)
    }

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
        case .idle:
            "idle"
        case .focusing:
            "focusing"
        case .paused:
            "paused"
        case .onBreak(let type):
            "break-\(type.rawValue)"
        }
    }

    private var controlsIdentity: String {
        "\(stateKey)-\(showStopConfirmation)"
    }

    private var stopConfirmationView: some View {
        PremiumSurface(style: .inset) {
            Text("End this session?")
                .font(FFType.meta.weight(.semibold))

            GlassEffectContainer {
                HStack(spacing: FFSpacing.xs) {
                    Button {
                        timerVM.stop()
                        showStopConfirmation = false
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(FFType.meta.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
                    }
                    .buttonStyle(.glass)

                    Button {
                        timerVM.abandonSession()
                        showStopConfirmation = false
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(FFType.meta.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
                    }
                    .buttonStyle(.glass)
                    .tint(FFColor.danger)

                    Button {
                        showStopConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(FFType.meta.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

}
