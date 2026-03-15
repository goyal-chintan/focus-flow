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
        VStack(alignment: .leading, spacing: 20) {
            Text("Log Focus Session")
                .font(.title3.weight(.semibold))

            projectSection
            durationSection
            whenSection
            moodSection
            achievementSection

            Divider()

            actionButtons
        }
        .padding(24)
        .frame(width: 380)
    }

    // MARK: - Sections

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Duration")

            durationPresets

            HStack {
                Text("Custom:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("min", value: $duration, format: .number)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .frame(width: 50)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: duration) {
                        startTime = Date().addingTimeInterval(TimeInterval(-max(5, duration) * 60))
                    }
                Text("minutes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var durationPresets: some View {
        HStack(spacing: 12) {
            ForEach([15, 25, 45, 60], id: \.self) { mins in
                DurationPresetButton(mins: mins, isSelected: duration == mins) {
                    duration = mins
                    startTime = Date().addingTimeInterval(TimeInterval(-mins * 60))
                }
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("When")
            DatePicker("Started at", selection: $startTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("What did you achieve?")
            TextField("e.g. Finished the API integration", text: $achievement)
                .textFieldStyle(.plain)
                .padding(8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionButtons: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glass)

            Button {
                save()
                dismiss()
            } label: {
                Text("Log Session")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .disabled(duration < 5)
        }
    }

    // MARK: - Helpers

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

// MARK: - Sub-components

private struct DurationPresetButton: View {
    let mins: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                Text("\(mins)m")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        } else {
            Button(action: action) {
                Text("\(mins)m")
                    .font(.system(size: 13, weight: .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
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
        } else {
            Button(action: action) { moodLabel }
                .buttonStyle(.glass)
        }
    }

    private var moodLabel: some View {
        VStack(spacing: 2) {
            Image(systemName: mood.icon)
                .font(.system(size: 14))
            Text(mood.rawValue)
                .font(.system(size: 9))
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
