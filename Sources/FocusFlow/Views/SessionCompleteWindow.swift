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
        .padding(18)
        .frame(width: 420)
    }

    private var focusHeaderSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Focus Complete")
                .font(.system(size: 20, weight: .semibold))

            Text("\(Int((timerVM.lastCompletedDuration ?? 0) / 60)) minutes · \(timerVM.lastCompletedLabel ?? "Focus")")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                LiquidMetricCard(
                    title: "Duration",
                    value: "\(Int((timerVM.lastCompletedDuration ?? 0) / 60))m",
                    icon: "timer",
                    color: .blue
                )

                LiquidMetricCard(
                    title: "Session",
                    value: timerVM.lastCompletedLabel ?? "Focus",
                    icon: "scope",
                    color: .green
                )

                if timerVM.isOvertime {
                    LiquidMetricCard(
                        title: "Overtime",
                        value: timerVM.overtimeTimeString,
                        icon: "plus.circle.fill",
                        color: .orange
                    )
                }
            }
        }
        .padding(.top, 8)
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LiquidSectionHeader("Reflection", subtitle: "Capture how this focus session felt")

            moodSection
            achievementSection
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How was your focus?")
                .font(.subheadline.weight(.medium))

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
                .tint(moodColor(mood))
        } else {
            Button { selectedMood = mood } label: { label }
                .buttonStyle(.glass)
        }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What did you achieve?")
                .font(.subheadline.weight(.medium))

            TextField("e.g. Finished the API integration", text: $achievement)
                .textFieldStyle(.plain)
                .padding(10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiquidSectionHeader("Project Allocation", subtitle: "Optionally split this session")

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
                LiquidGlassPanel(cornerRadius: LiquidDesignTokens.CornerRadius.control) {
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            .buttonStyle(.plain)

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
        GlassEffectContainer {
            VStack(spacing: 8) {
                LiquidActionButton(
                    title: "Take a Break",
                    icon: "cup.and.saucer.fill",
                    role: .primary,
                    tint: .green
                ) {
                    saveAndDismiss(action: .takeBreak)
                }

                HStack(spacing: 8) {
                    LiquidActionButton(
                        title: "Continue Focusing",
                        icon: "arrow.clockwise",
                        role: .secondary
                    ) {
                        saveAndDismiss(action: .continueFocusing)
                    }

                    LiquidActionButton(
                        title: "End Session",
                        icon: "stop.fill",
                        role: .destructive
                    ) {
                        saveAndDismiss(action: .endSession)
                    }
                }
            }
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
