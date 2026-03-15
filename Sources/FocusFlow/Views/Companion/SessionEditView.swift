import SwiftUI
import SwiftData

struct SessionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: FocusSession

    @State private var selectedMood: FocusMood?
    @State private var achievement: String
    @State private var selectedProject: Project?

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    init(session: FocusSession) {
        self.session = session
        _selectedMood = State(initialValue: session.mood)
        _achievement = State(initialValue: session.achievement ?? "")
        _selectedProject = State(initialValue: session.project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            sessionInfoSection
            Divider()
            projectSection
            moodSection
            achievementSection
            Divider()
            actionsSection
        }
        .padding(20)
        .frame(width: 340)
    }

    private var headerSection: some View {
        HStack {
            Text("Edit Session")
                .font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionInfoSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\u{00B7}")
                .foregroundStyle(.tertiary)
            Text(session.actualDuration.formattedFocusTime)
                .font(.subheadline.weight(.medium))
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus Quality")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(FocusMood.allCases, id: \.self) { mood in
                    moodButton(mood)
                }
            }
        }
    }

    @ViewBuilder
    private func moodButton(_ mood: FocusMood) -> some View {
        let isSelected = selectedMood == mood
        let label = VStack(spacing: 2) {
            Image(systemName: mood.icon)
                .font(.system(size: 14))
            Text(mood.rawValue)
                .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)

        if isSelected {
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
            Text("Achievement")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("What did you achieve?", text: $achievement)
                .textFieldStyle(.plain)
                .padding(8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionsSection: some View {
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
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        }
    }

    private func save() {
        session.project = selectedProject
        session.mood = selectedMood
        session.achievement = achievement.isEmpty ? nil : achievement
        try? modelContext.save()
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
