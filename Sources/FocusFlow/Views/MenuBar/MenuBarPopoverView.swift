import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var timerVM = timerVM

        VStack(spacing: 0) {
            // Timer ring section
            VStack(spacing: 14) {
                TimerRingView(
                    progress: timerVM.progress,
                    timeString: timerVM.state == .idle ? defaultTimeString : timerVM.timeString,
                    label: stateLabel,
                    state: timerVM.state
                )
                .padding(.top, 20)

                SessionDotsView(
                    completed: timerVM.completedFocusSessions % timerVM.sessionsBeforeLongBreak,
                    total: timerVM.sessionsBeforeLongBreak
                )
                .opacity(timerVM.state == .idle && timerVM.completedFocusSessions == 0 ? 0.4 : 1)
            }

            // Project picker (idle only)
            if timerVM.state == .idle {
                ProjectPickerView(
                    selectedProject: $timerVM.selectedProject,
                    customLabel: $timerVM.customLabel
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Controls
            controlsSection
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Divider()
                .padding(.top, 14)

            // Footer
            HStack(spacing: 0) {
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
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Open Stats")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timerVM.state)
    }

    @ViewBuilder
    private var controlsSection: some View {
        switch timerVM.state {
        case .idle:
            ControlButton(title: "Start Focus", icon: "play.fill", role: .primary) {
                timerVM.startFocus()
            }

        case .focusing:
            HStack(spacing: 8) {
                ControlButton(title: "Pause", icon: "pause.fill", role: .secondary) {
                    timerVM.pause()
                }
                ControlButton(title: "Stop", icon: "stop.fill", role: .destructive) {
                    timerVM.stop()
                }
            }

        case .paused:
            HStack(spacing: 8) {
                ControlButton(title: "Resume", icon: "play.fill", role: .primary) {
                    timerVM.resume()
                }
                ControlButton(title: "Stop", icon: "stop.fill", role: .destructive) {
                    timerVM.stop()
                }
            }

        case .onBreak:
            ControlButton(title: "Skip Break", icon: "forward.fill", role: .secondary) {
                timerVM.skipBreak()
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
        let mins = Int((timerVM.settings?.focusDuration ?? 1500) / 60)
        return String(format: "%02d:00", mins)
    }

    private var footerText: String {
        let sessions = timerVM.todaySessionCount
        let time = formattedTime(timerVM.todayFocusTime)
        if sessions == 0 { return "No sessions yet today" }
        return "\(sessions) session\(sessions == 1 ? "" : "s") · \(time) focused"
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
