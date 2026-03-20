import SwiftUI
import SwiftData

struct ManualSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    @State private var selectedProject: Project?
    @State private var duration: Int = 25
    @State private var startTime: Date = Date().addingTimeInterval(-25 * 60)
    @State private var selectedMood: FocusMood?
    @State private var achievement: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
                LiquidSectionHeader("Log Focus Session", subtitle: "Record work completed outside the active timer")

                projectSection
                durationSection
                whenSection
                moodSection
                achievementSection
                actionButtons
            }
            .padding(20)
        }
        .frame(width: 420)
        .background(.background)
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Project")

            Menu {
                Button("None") { selectedProject = nil }
                Divider()
                ForEach(projects) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        Label(project.name, systemImage: project.icon ?? "folder.fill")
                    }
                }
            } label: {
                HStack {
                    Text(selectedProject?.name ?? "No Project")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
            }
            .buttonStyle(.plain)
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Duration")

            HStack(spacing: 8) {
                ForEach([15, 25, 45, 60], id: \.self) { mins in
                    DurationPresetButton(mins: mins, isSelected: duration == mins) {
                        duration = mins
                        startTime = Date().addingTimeInterval(TimeInterval(-mins * 60))
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Custom")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                TextField("min", value: $duration, format: .number)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .frame(width: 58)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
                    .onChange(of: duration) {
                        startTime = Date().addingTimeInterval(TimeInterval(-max(5, duration) * 60))
                    }

                Text("minutes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("When")
            DatePicker(
                "Started at",
                selection: $startTime,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Focus Quality")

            HStack(spacing: 6) {
                ForEach(FocusMood.allCases, id: \.self) { mood in
                    MoodButton(mood: mood, isSelected: selectedMood == mood) {
                        selectedMood = selectedMood == mood ? nil : mood
                    }
                }
            }
        }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("What did you achieve?")

            TextField("e.g. Finished the API integration", text: $achievement)
                .textFieldStyle(.plain)
                .padding(8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: LiquidDesignTokens.Spacing.medium) {
            LiquidActionButton(
                title: "Cancel",
                icon: "xmark",
                role: .secondary
            ) {
                dismiss()
            }

            LiquidActionButton(
                title: "Log Session",
                icon: "checkmark",
                role: .primary
            ) {
                save()
                dismiss()
            }
            .disabled(duration < 5)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func save() {
        let clampedDuration = max(5, duration)
        let session = FocusSession(
            type: .focus,
            duration: TimeInterval(clampedDuration * 60),
            project: selectedProject
        )
        session.startedAt = startTime
        session.endedAt = startTime.addingTimeInterval(TimeInterval(clampedDuration * 60))
        session.completed = true
        session.mood = selectedMood
        session.achievement = achievement.isEmpty ? nil : achievement
        modelContext.insert(session)
        try? modelContext.save()
    }
}

private struct DurationPresetButton: View {
    let mins: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let label = Text("\(mins)m")
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

        if isSelected {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .buttonBorderShape(.capsule)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }
}

private struct MoodButton: View {
    let mood: FocusMood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) { moodLabel }
                .buttonStyle(.glassProminent)
                .tint(moodColor)
                .buttonBorderShape(.roundedRectangle(radius: 12))
        } else {
            Button(action: action) { moodLabel }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 12))
        }
    }

    private var moodLabel: some View {
        VStack(spacing: 2) {
            Image(systemName: mood.icon)
                .font(.system(size: 14))
            Text(mood.rawValue)
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var moodColor: Color {
        switch mood {
        case .distracted: .orange
        case .neutral: .secondary
        case .focused: .blue
        case .deepFocus: .purple
        }
    }
}
