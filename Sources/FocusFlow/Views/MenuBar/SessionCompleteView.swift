import SwiftUI

struct SessionCompleteView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @State private var selectedMood: FocusMood? = nil
    @State private var achievement: String = ""
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.xl) {
                headerSection
                moodSection
                achievementSection
                splitSection
                actionsSection
            }
            .padding(FFSpacing.lg)
        }
        .frame(width: 400)
    }

    // MARK: - Header (no card wrapper — floats on popover glass)

    private var headerSection: some View {
        VStack(spacing: FFSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(FFColor.success)

            Text("Focus Complete")
                .font(FFType.titleLarge)

            Text("\(completedMinutes) minutes \u{00B7} \(timerVM.lastCompletedLabel ?? "Focus")")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, FFSpacing.sm)
    }

    // MARK: - Mood (glass buttons directly — no card wrapper)

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("How was your focus?")
                .font(FFType.callout)

            GlassEffectContainer {
                HStack(spacing: FFSpacing.sm) {
                    ForEach(FocusMood.allCases, id: \.self) { mood in
                        moodButton(for: mood)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func moodButton(for mood: FocusMood) -> some View {
        let label = VStack(spacing: FFSpacing.xs) {
            Image(systemName: mood.icon)
                .font(.system(size: 20, weight: .semibold))
            Text(mood.rawValue)
                .font(FFType.meta)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FFSpacing.md)

        if selectedMood == mood {
            Button { selectedMood = mood } label: { label }
                .buttonStyle(.glassProminent)
                .tint(moodColor(mood))
        } else {
            Button { selectedMood = mood } label: { label }
                .buttonStyle(.glass)
        }
    }

    // MARK: - Achievement (glass text field — no card wrapper)

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("What did you achieve?")
                .font(FFType.callout)

            TextField("Finished the API integration, wrote the design doc...", text: $achievement)
                .textFieldStyle(.plain)
                .font(FFType.body)
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
        }
    }

    // MARK: - Split (disclosure — no card wrapper)

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                HStack(spacing: FFSpacing.sm) {
                    Image(systemName: showSplits ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FFColor.focus)

                    Text("Split time across projects")
                        .font(FFType.callout)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: showSplits ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, FFSpacing.xs)
            }
            .buttonStyle(.glass)

            if showSplits {
                TimeSplitView(
                    totalDuration: timerVM.lastCompletedDuration ?? 0,
                    splits: $splits
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Actions (glass buttons directly — no card wrapper)

    private var actionsSection: some View {
        GlassEffectContainer {
            VStack(spacing: FFSpacing.sm) {
                Button {
                    timerVM.saveReflection(mood: selectedMood, achievement: normalizedAchievement, splits: showSplits ? splits : nil)
                    timerVM.continueAfterCompletion(action: .takeBreak)
                } label: {
                    Label("Take a Break", systemImage: "cup.and.saucer.fill")
                        .font(FFType.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FFSpacing.sm)
                }
                .buttonStyle(.glassProminent)
                .tint(FFColor.success)

                HStack(spacing: FFSpacing.sm) {
                    Button {
                        timerVM.saveReflection(mood: selectedMood, achievement: normalizedAchievement, splits: showSplits ? splits : nil)
                        timerVM.continueAfterCompletion(action: .continueFocusing)
                    } label: {
                        Label("Continue", systemImage: "arrow.clockwise")
                            .font(FFType.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
                    }
                    .buttonStyle(.glass)

                    Button {
                        timerVM.saveReflection(mood: selectedMood, achievement: normalizedAchievement, splits: showSplits ? splits : nil)
                        timerVM.continueAfterCompletion(action: .endSession)
                    } label: {
                        Label("End Session", systemImage: "stop.fill")
                            .font(FFType.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FFSpacing.sm)
                    }
                    .buttonStyle(.glass)
                    .tint(FFColor.danger)
                }
            }
        }
    }

    // MARK: - Helpers

    private var completedMinutes: Int {
        Int((timerVM.lastCompletedDuration ?? 0) / 60)
    }

    private var normalizedAchievement: String? {
        let trimmed = achievement.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func moodColor(_ mood: FocusMood) -> Color {
        switch mood {
        case .distracted: FFColor.warning
        case .neutral: .secondary
        case .focused: FFColor.focus
        case .deepFocus: FFColor.deepFocus
        }
    }
}
