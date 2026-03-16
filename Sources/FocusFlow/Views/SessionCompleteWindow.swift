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
            // Bring completion window to front of all apps
            // Required for LSUIElement menu bar apps
            NSApplication.shared.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for window in NSApplication.shared.windows {
                    if window.title == "Session Complete" {
                        window.level = .floating
                        window.makeKeyAndOrderFront(nil)
                        window.center()
                        break
                    }
                }
            }
        }
    }

    // MARK: - Focus Completion

    private var focusContent: some View {
        VStack(spacing: 20) {
            focusHeaderSection
            Divider()
            moodSection
            achievementSection
            splitSection
            Divider()
            focusActionsSection
        }
        .padding(20)
        .frame(width: 380)
    }

    private var focusHeaderSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Focus Complete")
                .font(.system(size: 20, weight: .semibold))

            Text("\(Int((timerVM.lastCompletedDuration ?? 0) / 60)) minutes \u{00B7} \(timerVM.lastCompletedLabel ?? "Focus")")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if timerVM.isOvertime {
                Text(timerVM.overtimeTimeString)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 8)
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Button {
                    saveAndDismiss(action: .takeBreak)
                } label: {
                    Label("Take a Break", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.green)

                HStack(spacing: 8) {
                    Button {
                        saveAndDismiss(action: .continueFocusing)
                    } label: {
                        Label("Continue Focusing", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)

                    Button {
                        saveAndDismiss(action: .endSession)
                    } label: {
                        Label("End Session", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
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
        VStack(spacing: 20) {
            breakHeaderSection
            Divider()
            breakActionsSection
        }
        .padding(20)
        .frame(width: 320)
    }

    private var breakHeaderSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Break Complete")
                .font(.system(size: 20, weight: .semibold))

            if timerVM.isOvertime {
                Text(timerVM.overtimeTimeString)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 8)
    }

    private var breakActionsSection: some View {
        GlassEffectContainer {
            VStack(spacing: 8) {
                Button {
                    timerVM.continueAfterCompletion(action: .continueFocusing)
                    dismissWindow(id: "session-complete")
                } label: {
                    Label("Start Focusing", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)

                Button {
                    timerVM.continueAfterCompletion(action: .endSession)
                    dismissWindow(id: "session-complete")
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
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
}
