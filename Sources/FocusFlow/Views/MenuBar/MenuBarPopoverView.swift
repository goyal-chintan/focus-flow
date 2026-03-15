import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.openWindow) private var openWindow
    @State private var showStopConfirmation = false

    var body: some View {
        if timerVM.showSessionComplete {
            SessionCompleteView()
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        @Bindable var timerVM = timerVM

        return VStack(spacing: 0) {
            // Timer ring
            TimerRingView(
                progress: timerVM.progress,
                timeString: timerVM.state == .idle ? defaultTimeString : timerVM.timeString,
                label: stateLabel,
                state: timerVM.state
            )
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Session dots
            SessionDotsView(
                completed: timerVM.completedFocusSessions % timerVM.sessionsBeforeLongBreak,
                total: timerVM.sessionsBeforeLongBreak
            )
            .opacity(timerVM.state == .idle && timerVM.completedFocusSessions == 0 ? 0.4 : 1)

            // Project picker and duration selector (idle only)
            if timerVM.state == .idle {
                idleSection
            }

            // Glass controls
            GlassEffectContainer {
                controlsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Subtle divider
            Divider()
                .padding(.top, 16)

            // Footer
            footerSection
        }
        .frame(width: 300)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timerVM.state)
    }

    private var idleSection: some View {
        @Bindable var timerVM = timerVM

        return VStack(spacing: 0) {
            ProjectPickerView(
                selectedProject: $timerVM.selectedProject,
                customLabel: $timerVM.customLabel
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)

            durationPresetButtons
                .padding(.horizontal, 20)
                .padding(.top, 12)

            customDurationInput
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var durationPresetButtons: some View {
        HStack(spacing: 0) {
            durationButton(mins: 15)
            durationButton(mins: 25)
            durationButton(mins: 45)
            durationButton(mins: 60)
        }
    }

    @ViewBuilder
    private func durationButton(mins: Int) -> some View {
        let isSelected = timerVM.selectedMinutes == mins
        let label = Text("\(mins)")
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

        if isSelected {
            Button { timerVM.selectedMinutes = mins } label: { label }
                .buttonStyle(.glassProminent)
                .tint(.blue)
        } else {
            Button { timerVM.selectedMinutes = mins } label: { label }
                .buttonStyle(.glass)
        }
    }

    private var customDurationInput: some View {
        @Bindable var timerVM = timerVM

        return HStack {
            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("Custom min", value: $timerVM.selectedMinutes, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 50)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
            Text("min")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        switch timerVM.state {
        case .idle:
            ControlButton(title: "Start Focus", icon: "play.fill", role: .primary) {
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

    private var footerSection: some View {
        HStack {
            Label {
                Text(footerText)
                    .font(.caption)
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
                Label("Stats", systemImage: "chart.bar.fill")
                    .font(.caption)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
        VStack(spacing: 8) {
            Text("End this session?")
                .font(.caption.weight(.medium))

            GlassEffectContainer {
                HStack(spacing: 8) {
                    Button {
                        timerVM.stop()
                        showStopConfirmation = false
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)

                    Button {
                        timerVM.abandonSession()
                        showStopConfirmation = false
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .tint(.red)

                    Button {
                        showStopConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

}
