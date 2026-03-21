import SwiftUI
import SwiftData

struct SessionCompleteView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Query private var allSettings: [AppSettings]
    @State private var selectedMood: FocusMood? = nil
    @State private var achievement: String = ""
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []
    @State private var selectedReminderItems: [RemindersService.ReminderItem] = []
    @State private var showReminderPicker = false

    private var settings: AppSettings? { allSettings.first }

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            Divider()
            moodSection
            achievementSection
            remindersSection
            splitSection
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
            Button { selectedMood = nil } label: { label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
        } else {
            Button { selectedMood = mood } label: { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 12))
        }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What did you achieve?")
                .font(.subheadline.weight(.medium))

            TextField("Log your wins — one per line...", text: $achievement, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.plain)
                .padding(10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))

            if !achievement.isEmpty {
                let items = achievement.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 5) {
                            Text("•")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                            Text(item.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Linked reminders")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if settings?.remindersIntegrationEnabled == true {
                    Button {
                        showReminderPicker = true
                    } label: {
                        Label("Attach", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
            }

            if settings?.remindersIntegrationEnabled != true {
                Text("Enable Reminders sync in Settings to link tasks.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if selectedReminderItems.isEmpty {
                Text("No reminders linked")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(selectedReminderItems, id: \.id) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "checklist")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.blue)
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                selectedReminderItems.removeAll(where: { $0.id == item.id })
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Remove reminder")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showReminderPicker) {
            ReminderSelectionSheet(
                selectedDate: Date(),
                selectedListId: settings?.selectedReminderListId,
                initialSelectedIds: Set(selectedReminderItems.map(\.id))
            ) { chosen in
                selectedReminderItems = chosen
            }
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var actionsSection: some View {
        VStack(spacing: 8) {
            takeBreakButton
            HStack(spacing: 8) {
                skipBreakButton
                continueFocusingButton
            }
            endSessionButton
        }
    }

    private var takeBreakButton: some View {
        Button {
            timerVM.saveReflection(
                mood: selectedMood,
                achievement: achievement.isEmpty ? nil : achievement,
                reminderIdsToComplete: selectedReminderItems.map(\.id),
                splits: showSplits ? splits : nil
            )
            timerVM.continueAfterCompletion(action: .takeBreak)
        } label: {
            Label("Take a Break", systemImage: "cup.and.saucer.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .tint(LiquidDesignTokens.Spectral.primaryContainer)
        .buttonBorderShape(.capsule)
    }

    private var skipBreakButton: some View {
        Button {
            timerVM.saveReflection(
                mood: selectedMood,
                achievement: achievement.isEmpty ? nil : achievement,
                reminderIdsToComplete: selectedReminderItems.map(\.id),
                splits: showSplits ? splits : nil
            )
            timerVM.continueAfterCompletion(action: .continueFocusing)
        } label: {
            Label("Skip Break", systemImage: "forward.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    private var continueFocusingButton: some View {
        Button {
            timerVM.saveReflection(
                mood: selectedMood,
                achievement: achievement.isEmpty ? nil : achievement,
                reminderIdsToComplete: selectedReminderItems.map(\.id),
                splits: showSplits ? splits : nil
            )
            timerVM.showSessionComplete = false
        } label: {
            Label("Continue Focusing", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    private var endSessionButton: some View {
        Button {
            timerVM.saveReflection(
                mood: selectedMood,
                achievement: achievement.isEmpty ? nil : achievement,
                reminderIdsToComplete: selectedReminderItems.map(\.id),
                splits: showSplits ? splits : nil
            )
            timerVM.continueAfterCompletion(action: .endSession)
        } label: {
            Label("Finish Session", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
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
