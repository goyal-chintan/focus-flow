import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @State private var showStopConfirmation = false

    @State private var didConfigure = false

    var body: some View {
        content
            .task(id: didConfigure) {
                if !didConfigure {
                    didConfigure = true
                    timerVM.ensureConfigured(modelContext: modelContext)
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

        return VStack(spacing: FFSpacing.lg) {
            heroSection

            if timerVM.state == .idle {
                idleSection
            } else {
                stateContextSection
            }

            actionDeck

            footerSection
        }
        .padding(FFSpacing.lg)
        .frame(width: 392)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timerVM.state)
    }

    private var heroSection: some View {
        PremiumSurface(style: .hero, alignment: .center) {
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

            if let heroContextCopy {
                Text(heroContextCopy)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var idleSection: some View {
        @Bindable var timerVM = timerVM

        return PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Focus Setup",
                eyebrow: "Ready",
                subtitle: "Set your project and session length before you start."
            )

            ProjectPickerView(
                selectedProject: $timerVM.selectedProject
            )

            durationPresetButtons

            customDurationInput
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
        } else {
            Button { timerVM.selectedMinutes = mins } label: { label }
                .buttonStyle(.glass)
        }
    }

    private var customDurationInput: some View {
        @Bindable var timerVM = timerVM

        return PremiumSurface(style: .inset) {
            HStack(spacing: FFSpacing.sm) {
                Text("Custom duration")
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
    }

    private var stateContextSection: some View {
        PremiumSurface(style: .card) {
            switch timerVM.state {
            case .focusing:
                PremiumSectionHeader(
                    "In Session",
                    eyebrow: "Focus",
                    subtitle: timerVM.selectedProject?.name ?? "Deep work in progress"
                )

                statusRow(label: "Blocking", value: timerVM.isBlockingActive ? "Active" : "Off", accent: timerVM.isBlockingActive ? .green : .secondary)
                statusRow(label: "Today's focus", value: timerVM.todayFocusTime.formattedFocusTime, accent: .secondary)

            case .paused:
                PremiumSectionHeader(
                    "Paused",
                    eyebrow: "Hold",
                    subtitle: pauseDescriptor
                )

                statusRow(label: "Paused for", value: timerVM.pauseTimeString, accent: timerVM.pauseWarningLevel.color)
                statusRow(label: "Project", value: timerVM.selectedProject?.name ?? "No project", accent: .secondary)

            case .onBreak(let type):
                PremiumSectionHeader(
                    type.displayName,
                    eyebrow: "Recovery",
                    subtitle: breakDescriptor
                )

                statusRow(label: "Completed today", value: "\(timerVM.todaySessionCount) sessions", accent: .secondary)
                statusRow(label: "Up next", value: "Another focus session", accent: FFColor.focus)

            case .idle:
                EmptyView()
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func statusRow(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: FFSpacing.sm) {
            Text(label)
                .font(FFType.meta)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(FFType.meta.weight(.semibold))
                .foregroundStyle(accent)
        }
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
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                actionDeckTitle,
                eyebrow: actionDeckEyebrow,
                subtitle: actionDeckSubtitle
            )

            GlassEffectContainer {
                controlsSection
            }
        }
    }

    private var footerSection: some View {
        PremiumSurface(style: .inset) {
            HStack(spacing: FFSpacing.sm) {
                if timerVM.isBlockingActive {
                    HStack(spacing: FFSpacing.xs) {
                        Image(systemName: "shield.checkered")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Blocking")
                            .font(FFType.meta)
                            .foregroundStyle(.green)
                    }
                    Text("\u{00B7}").foregroundStyle(.tertiary)
                }

                Label {
                    Text(footerText)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
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
                    Label("Open Companion", systemImage: "chart.bar.fill")
                        .font(FFType.meta)
                }
                .buttonStyle(.glass)
            }
        }
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

    private var heroContextCopy: String? {
        switch timerVM.state {
        case .idle:
            return timerVM.selectedProject?.name ?? "Choose a project and start a premium focus block."
        case .focusing:
            return timerVM.selectedProject?.name ?? "You are in a live focus session."
        case .paused:
            return "Resume when you are ready. Longer pauses will lower session quality."
        case .onBreak(let type):
            return type == .longBreak ? "Take a real reset before the next round." : "A short break helps you sustain depth."
        }
    }

    private var actionDeckTitle: String {
        switch timerVM.state {
        case .idle: "Start Session"
        case .focusing: "Session Controls"
        case .paused: "Pause Controls"
        case .onBreak: "Break Controls"
        }
    }

    private var actionDeckEyebrow: String? {
        switch timerVM.state {
        case .idle: "Action"
        case .focusing: "Live"
        case .paused: "Attention"
        case .onBreak: "Optional"
        }
    }

    private var actionDeckSubtitle: String? {
        switch timerVM.state {
        case .idle:
            return "Begin the next focus block when everything looks right."
        case .focusing:
            return "Pause if needed, or end the session and save or discard it."
        case .paused:
            return "Resume soon to protect your momentum."
        case .onBreak:
            return "Skip ahead if you are ready to return early."
        }
    }

    private var pauseDescriptor: String {
        switch timerVM.pauseWarningLevel {
        case .normal:
            return "A short pause is fine. Resume when you are ready."
        case .warning:
            return "Your pause is stretching out. Consider returning soon."
        case .critical:
            return "This session is cooling off. Resume or stop decisively."
        }
    }

    private var breakDescriptor: String {
        "Step away for a moment so the next session starts fresh."
    }

}
