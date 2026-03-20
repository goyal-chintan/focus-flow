import SwiftUI
import SwiftData

struct SessionCompleteWindowView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedMood: FocusMood? = nil
    @State private var achievement: String = ""
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []

    private var isBreakCompletion: Bool {
        timerVM.lastCompletedSession?.type != .focus
    }

    var body: some View {
        Group {
            if isBreakCompletion {
                breakContent
            } else {
                focusContent
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            bringWindowToFront()
        }
    }

    // MARK: - Focus Completion

    private var focusContent: some View {
        VStack(spacing: 16) {
            focusHeaderSection
            reflectionSection
            splitSection
            focusActionsSection
        }
        .padding(24)
        .frame(width: 440)
    }

    private var focusHeaderSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(LiquidDesignTokens.Spectral.primaryContainer)

            Text("Session Complete")
                .font(.system(size: 24, weight: .bold))

            TrackedLabel(
                text: "FocusFlow macOS Experience",
                font: .system(size: 10, weight: .medium),
                color: LiquidDesignTokens.Surface.onSurfaceMuted,
                tracking: 2.0
            )

            HStack(spacing: 10) {
                statCard(
                    label: "Time Elapsed",
                    value: "\(Int((timerVM.lastCompletedDuration ?? 0) / 60))m Session",
                    valueColor: LiquidDesignTokens.Spectral.electricBlue
                )

                statCard(
                    label: "Active Project",
                    value: timerVM.lastCompletedLabel ?? "Focus",
                    valueColor: LiquidDesignTokens.Surface.onSurface
                )
            }
        }
        .padding(.top, 8)
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            moodSection
            achievementSection
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(
                text: "How Was Your Focus?",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )

            HStack(spacing: 8) {
                ForEach(FocusMood.allCases, id: \.self) { mood in
                    moodButton(for: mood)
                }
            }
        }
    }

    @ViewBuilder
    private func moodButton(for mood: FocusMood) -> some View {
        let label = VStack(spacing: 4) {
            Image(systemName: mood.icon)
                .font(.system(size: 16))
            Text(mood.rawValue)
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        if selectedMood == mood {
            Button { selectedMood = nil } label: { label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(moodColor(mood))
                .accessibilityLabel("\(mood.rawValue), selected")
        } else {
            Button { selectedMood = mood } label: { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .accessibilityLabel(mood.rawValue)
        }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrackedLabel(
                text: "What Did You Finish?",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )

            TextField("Log your wins...", text: $achievement)
                .textFieldStyle(.plain)
                .padding(10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(
                text: "Project Allocation",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSplits.toggle()
                    if showSplits && splits.isEmpty {
                        let totalMins = Int((timerVM.lastCompletedDuration ?? 0) / 60)
                        splits = [TimeSplitView.SplitEntry(
                            project: timerVM.selectedProject,
                            customLabel: timerVM.customLabel,
                            minutes: totalMins
                        )]
                    }
                }
            } label: {
                HStack {
                    Image(systemName: showSplits ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                        .font(.caption)
                    Text("Split across projects")
                        .font(.caption)
                    Spacer()
                    Image(systemName: showSplits ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 12))

            if showSplits {
                TimeSplitView(
                    totalDuration: timerVM.lastCompletedDuration ?? 0,
                    splits: $splits
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var focusActionsSection: some View {
        VStack(spacing: 12) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    Button {
                        saveAndDismiss(action: .takeBreak)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 12))
                            Text("Take a Break")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)

                    Button {
                        saveAndDismiss(action: .continueFocusing)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Keep Focusing")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(LiquidDesignTokens.Spectral.primaryContainer)
                    .buttonBorderShape(.capsule)
                }
            }

            Button {
                saveAndDismiss(action: .endSession)
            } label: {
                TrackedLabel(
                    text: "Done",
                    font: .system(size: 11, weight: .medium),
                    color: LiquidDesignTokens.Surface.onSurfaceMuted,
                    tracking: 2.5
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func saveAndDismiss(action: PostCompletionAction) {
        timerVM.saveReflection(
            mood: selectedMood,
            achievement: achievement.isEmpty ? nil : achievement,
            splits: showSplits ? splits : nil
        )
        timerVM.continueAfterCompletion(action: action)
        dismissWindow(id: "session-complete")
    }

    // MARK: - Break Completion

    private var breakContent: some View {
        VStack(spacing: 16) {
            breakHeaderSection
            breakActionsSection
        }
        .padding(18)
        .frame(width: 340)
    }

    private var breakHeaderSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Break Complete")
                .font(.system(size: 20, weight: .semibold))

            if timerVM.isOvertime {
                LiquidMetricCard(
                    title: "Overtime",
                    value: timerVM.overtimeTimeString,
                    icon: "plus.circle.fill",
                    color: .orange
                )
                .frame(maxWidth: 180)
            }
        }
        .padding(.top, 8)
    }

    private var breakActionsSection: some View {
        GlassEffectContainer {
            VStack(spacing: 8) {
                LiquidActionButton(
                    title: "Start Focusing",
                    icon: "play.fill",
                    role: .primary,
                    tint: .blue
                ) {
                    timerVM.continueAfterCompletion(action: .continueFocusing)
                    dismissWindow(id: "session-complete")
                }

                LiquidActionButton(
                    title: "End",
                    icon: "stop.fill",
                    role: .secondary
                ) {
                    timerVM.continueAfterCompletion(action: .endSession)
                    dismissWindow(id: "session-complete")
                }
            }
        }
    }

    // MARK: - Helpers

    private func moodColor(_ mood: FocusMood) -> Color {
        switch mood {
        case .distracted: .orange
        case .neutral: .secondary
        case .focused: .blue
        case .deepFocus: .purple
        }
    }

    private func statCard(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TrackedLabel(
                text: label,
                font: .system(size: 10, weight: .semibold),
                tracking: 1.5
            )

            Text(value)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bringWindowToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Try immediately and with delays to catch the window at different lifecycle stages
        for delay in [0.0, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Find our window — match by content size since hiddenTitleBar may blank the title
                let allWindows = NSApplication.shared.windows
                NSLog("FocusFlow: [delay=\(delay)] window count=\(allWindows.count), titles=\(allWindows.map { $0.title })")
                for window in allWindows {
                    // Match by: not the menu bar panel, not the stats window, has content
                    if window.title == "Session Complete" || window.identifier?.rawValue.contains("session-complete") == true {
                        NSLog("FocusFlow: Found window by title/id: \(window.title)")
                        window.level = .floating
                        window.makeKeyAndOrderFront(nil)
                        window.center()
                        return
                    }
                }
                // Fallback: find the newest non-panel window that isn't the stats window
                if let window = allWindows.last(where: {
                    !$0.title.isEmpty && $0.title != "FocusFlow" && !($0 is NSPanel) && $0.isVisible
                }) {
                    NSLog("FocusFlow: Fallback window: \(window.title) frame=\(window.frame)")
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    window.center()
                }
            }
        }
    }
}
