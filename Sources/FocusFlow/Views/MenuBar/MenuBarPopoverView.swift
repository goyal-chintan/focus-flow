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
        VStack(spacing: 0) {
            timerHeroSection

            stateSection
                .padding(.top, 14)

            Divider()
                .padding(.top, 16)

            footerSection
        }
        .frame(width: 316)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: timerVM.state)
    }

    private var timerHeroSection: some View {
        VStack(spacing: 10) {
            TimerRingView(
                progress: timerVM.progress,
                timeString: timerVM.state == .idle ? defaultTimeString : timerVM.timeString,
                label: stateLabel,
                state: timerVM.state
            )
            .padding(.top, 22)

            SessionDotsView(
                completed: timerVM.completedFocusSessions % timerVM.sessionsBeforeLongBreak,
                total: timerVM.sessionsBeforeLongBreak
            )
            .opacity(timerVM.state == .idle && timerVM.completedFocusSessions == 0 ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch timerVM.state {
        case .idle:
            idleStateSection
        case .focusing:
            focusingStateSection
        case .paused:
            pausedStateSection
        case .onBreak:
            breakStateSection
        }
    }

    private var idleStateSection: some View {
        @Bindable var timerVM = timerVM

        return IdlePopoverStateView(
            selectedProject: $timerVM.selectedProject,
            selectedMinutes: $timerVM.selectedMinutes
        ) {
            timerVM.ensureConfigured(modelContext: modelContext)
            timerVM.startFocus()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var focusingStateSection: some View {
        FocusingPopoverStateView(
            showStopConfirmation: $showStopConfirmation,
            onPause: { timerVM.pause() },
            onShowStopConfirmation: {
                withAnimation {
                    showStopConfirmation = true
                }
            },
            onSaveStop: {
                timerVM.stop()
                showStopConfirmation = false
            },
            onDiscardStop: {
                timerVM.abandonSession()
                showStopConfirmation = false
            },
            onCancelStop: { showStopConfirmation = false }
        )
        .padding(.horizontal, 20)
        .transition(.opacity)
    }

    private var pausedStateSection: some View {
        PausedPopoverStateView(
            pauseTimeString: timerVM.pauseTimeString,
            pauseWarningColor: timerVM.pauseWarningLevel.color,
            showStopConfirmation: $showStopConfirmation,
            onResume: { timerVM.resume() },
            onShowStopConfirmation: {
                withAnimation {
                    showStopConfirmation = true
                }
            },
            onSaveStop: {
                timerVM.stop()
                showStopConfirmation = false
            },
            onDiscardStop: {
                timerVM.abandonSession()
                showStopConfirmation = false
            },
            onCancelStop: { showStopConfirmation = false }
        )
        .padding(.horizontal, 20)
        .transition(.opacity)
    }

    private var breakStateSection: some View {
        BreakPopoverStateView {
            timerVM.skipBreak()
        }
        .padding(.horizontal, 20)
        .transition(.opacity)
    }

    private var footerSection: some View {
        HStack(spacing: 8) {
            if timerVM.isBlockingActive {
                HStack(spacing: 4) {
                    Image(systemName: "shield.checkered")
                        .font(.caption)
                    Text("Blocking")
                        .font(.caption)
                }
                .foregroundStyle(.green)

                Text("·")
                    .foregroundStyle(.tertiary)
            }

            Label {
                Text(footerText)
                    .font(.caption)
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
                    .font(.caption)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var stateLabel: String {
        switch timerVM.state {
        case .idle:
            "Ready to Focus"
        case .focusing:
            timerVM.sessionLabel
        case .paused:
            "Paused"
        case .onBreak(let type):
            type.displayName
        }
    }

    private var defaultTimeString: String {
        let mins = max(5, timerVM.selectedMinutes)
        return String(format: "%02d:00", mins)
    }

    private var footerText: String {
        let sessions = timerVM.todaySessionCount
        let time = timerVM.todayFocusTime.formattedFocusTime
        if sessions == 0 {
            return "No sessions yet today"
        }
        return "\(sessions) session\(sessions == 1 ? "" : "s") · \(time) focused"
    }
}

private struct IdlePopoverStateView: View {
    @Binding var selectedProject: Project?
    @Binding var selectedMinutes: Int
    let onStartFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProjectPickerView(selectedProject: $selectedProject)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            DurationPresetRow(selectedMinutes: $selectedMinutes)
                .padding(.horizontal, 20)

            CustomDurationInput(selectedMinutes: $selectedMinutes)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            GlassEffectContainer {
                ControlButton(title: "Start Focus", icon: "play.fill", role: .primary, action: onStartFocus)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }
}

private struct DurationPresetRow: View {
    @Binding var selectedMinutes: Int

    private let presets = [15, 25, 45, 60]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(presets, id: \.self) { minutes in
                DurationPresetButton(minutes: minutes, selectedMinutes: $selectedMinutes)
            }
        }
    }
}

private struct DurationPresetButton: View {
    let minutes: Int
    @Binding var selectedMinutes: Int

    private var isSelected: Bool { selectedMinutes == minutes }

    var body: some View {
        let label = Text("\(minutes)")
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

        if isSelected {
            Button {
                selectedMinutes = minutes
            } label: {
                label
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        } else {
            Button {
                selectedMinutes = minutes
            } label: {
                label
            }
            .buttonStyle(.glass)
        }
    }
}

private struct CustomDurationInput: View {
    @Binding var selectedMinutes: Int

    var body: some View {
        HStack {
            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)

            TextField("Custom min", value: $selectedMinutes, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 58)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))

            Text("min")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct FocusingPopoverStateView: View {
    @Binding var showStopConfirmation: Bool
    let onPause: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ControlButton(title: "Pause", icon: "pause.fill", role: .secondary, action: onPause)
                    ControlButton(title: "Stop", icon: "stop.fill", role: .destructive, action: onShowStopConfirmation)
                }

                if showStopConfirmation {
                    StopConfirmationView(
                        onSaveStop: onSaveStop,
                        onDiscardStop: onDiscardStop,
                        onCancel: onCancelStop
                    )
                }
            }
        }
    }
}

private struct PausedPopoverStateView: View {
    let pauseTimeString: String
    let pauseWarningColor: Color
    @Binding var showStopConfirmation: Bool
    let onResume: () -> Void
    let onShowStopConfirmation: () -> Void
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancelStop: () -> Void

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text("Paused for")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(pauseTimeString)
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(pauseWarningColor)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: pauseTimeString)
                }

                HStack(spacing: 8) {
                    ControlButton(title: "Resume", icon: "play.fill", role: .primary, action: onResume)
                    ControlButton(title: "Stop", icon: "stop.fill", role: .destructive, action: onShowStopConfirmation)
                }

                if showStopConfirmation {
                    StopConfirmationView(
                        onSaveStop: onSaveStop,
                        onDiscardStop: onDiscardStop,
                        onCancel: onCancelStop
                    )
                }
            }
        }
    }
}

private struct BreakPopoverStateView: View {
    let onSkipBreak: () -> Void

    var body: some View {
        GlassEffectContainer {
            ControlButton(title: "Skip Break", icon: "forward.fill", role: .secondary, action: onSkipBreak)
        }
    }
}

private struct StopConfirmationView: View {
    let onSaveStop: () -> Void
    let onDiscardStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("End this session?")
                .font(.caption.weight(.medium))

            HStack(spacing: 8) {
                Button(action: onSaveStop) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)

                Button(action: onDiscardStop) {
                    Label("Discard", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .tint(.red)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
