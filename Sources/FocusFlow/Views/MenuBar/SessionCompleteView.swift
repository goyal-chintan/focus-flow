import SwiftUI

struct SessionCompleteView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @State private var selectedMood: FocusMood? = nil
    @State private var achievement: String = ""
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []

    var body: some View {
        VStack(spacing: FFSpacing.lg) {
            headerSection
            reflectionSection
            actionsSection
        }
        .padding(FFSpacing.lg)
        .frame(width: 432)
    }

    private var headerSection: some View {
        PremiumSurface(style: .hero, alignment: .center) {
            ZStack {
                RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous)
                    .fill(FFColor.success.opacity(0.14))
                    .frame(width: 72, height: 72)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(FFColor.success)
            }
            .frame(maxWidth: .infinity)

            Text("Focus Complete")
                .font(FFType.titleLarge)
                .frame(maxWidth: .infinity)

            Text("\(completedMinutes) minutes \u{00B7} \(timerVM.lastCompletedLabel ?? "Focus")")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Text("Capture how the session felt while it is still fresh.")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var reflectionSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Reflection",
                eyebrow: "Session Review",
                subtitle: "Rate the quality, jot down the outcome, and optionally split the time."
            )

            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("How was your focus?")
                    .font(FFType.callout)

                HStack(spacing: FFSpacing.sm) {
                    ForEach(FocusMood.allCases, id: \.self) { mood in
                        moodButton(for: mood)
                    }
                }
            }

            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("What did you achieve?")
                    .font(FFType.callout)

                TextField("Finished the API integration, wrote the design doc, cleaned up the tests...", text: $achievement)
                    .textFieldStyle(.plain)
                    .font(FFType.body)
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.sm)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1))
                    }
            }

            splitSection
        }
    }

    @ViewBuilder
    private func moodButton(for mood: FocusMood) -> some View {
        let label = VStack(spacing: FFSpacing.xs) {
            Image(systemName: mood.icon)
                .font(.system(size: 18, weight: .semibold))
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

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Button {
                withAnimation {
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
                    ZStack {
                        RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                            .fill(FFColor.focus.opacity(0.12))

                        Image(systemName: showSplits ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FFColor.focus)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allocate time across projects")
                            .font(FFType.callout)
                            .foregroundStyle(.primary)
                        Text(showSplits ? "Adjust the split before saving." : "Turn this on if the session covered more than one outcome.")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: showSplits ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))
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

    private var actionsSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Next Step",
                eyebrow: "Continue",
                subtitle: "Choose whether to recover, keep the momentum, or close the loop."
            )

            GlassEffectContainer {
                VStack(spacing: FFSpacing.sm) {
                    takeBreakButton
                    HStack(spacing: FFSpacing.sm) {
                        continueFocusingButton
                        endSessionButton
                    }
                }
            }
        }
    }

    private var takeBreakButton: some View {
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
    }

    private var continueFocusingButton: some View {
        Button {
            timerVM.saveReflection(mood: selectedMood, achievement: normalizedAchievement, splits: showSplits ? splits : nil)
            timerVM.continueAfterCompletion(action: .continueFocusing)
        } label: {
            Label("Continue", systemImage: "arrow.clockwise")
                .font(FFType.meta)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FFSpacing.sm)
        }
        .buttonStyle(.glass)
    }

    private var endSessionButton: some View {
        Button {
            timerVM.saveReflection(mood: selectedMood, achievement: normalizedAchievement, splits: showSplits ? splits : nil)
            timerVM.continueAfterCompletion(action: .endSession)
        } label: {
            Label("End Session", systemImage: "stop.fill")
                .font(FFType.meta)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FFSpacing.sm)
        }
        .buttonStyle(.glass)
        .tint(FFColor.danger)
    }

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
