import SwiftUI

struct SessionCompleteView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @State private var selectedMood: FocusMood? = nil
    @State private var achievement: String = ""

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            Divider()
            moodSection
            achievementSection
            Divider()
            actionsSection
        }
        .padding(20)
        .frame(width: 320)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Focus Complete")
                .font(.system(size: 18, weight: .semibold))

            Text("\(Int((timerVM.lastCompletedDuration ?? 0) / 60)) minutes \u{00B7} \(timerVM.lastCompletedLabel ?? "Focus")")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Button { selectedMood = mood } label: { label }
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

    private var actionsSection: some View {
        GlassEffectContainer {
            VStack(spacing: 8) {
                takeBreakButton
                HStack(spacing: 8) {
                    continueFocusingButton
                    endSessionButton
                }
            }
        }
    }

    private var takeBreakButton: some View {
        Button {
            timerVM.saveReflection(mood: selectedMood, achievement: achievement.isEmpty ? nil : achievement)
            timerVM.continueAfterCompletion(action: .takeBreak)
        } label: {
            Label("Take a Break", systemImage: "cup.and.saucer.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .tint(.green)
    }

    private var continueFocusingButton: some View {
        Button {
            timerVM.saveReflection(mood: selectedMood, achievement: achievement.isEmpty ? nil : achievement)
            timerVM.continueAfterCompletion(action: .continueFocusing)
        } label: {
            Label("Continue Focusing", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
    }

    private var endSessionButton: some View {
        Button {
            timerVM.saveReflection(mood: selectedMood, achievement: achievement.isEmpty ? nil : achievement)
            timerVM.continueAfterCompletion(action: .endSession)
        } label: {
            Label("End Session", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .tint(.red)
    }

    private func moodColor(_ mood: FocusMood) -> Color {
        switch mood {
        case .distracted: .orange
        case .neutral: .secondary
        case .focused: .blue
        case .deepFocus: .purple
        }
    }
}
