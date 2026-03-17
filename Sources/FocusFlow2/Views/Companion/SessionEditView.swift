import SwiftUI
import SwiftData

struct SessionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: FocusSession

    @State private var selectedMood: FocusMood?
    @State private var achievement: String
    @State private var selectedProject: Project?
    @State private var editedDuration: TimeInterval
    @State private var editedStartedAt: Date
    @State private var editedEndedAt: Date
    @State private var selectedDurationMinutes: Int

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    init(session: FocusSession) {
        self.session = session
        _selectedMood = State(initialValue: session.mood)
        _achievement = State(initialValue: session.achievement ?? "")
        _selectedProject = State(initialValue: session.project)
        _editedDuration = State(initialValue: session.duration)
        _editedStartedAt = State(initialValue: session.startedAt)
        _editedEndedAt = State(initialValue: session.endedAt ?? session.startedAt.addingTimeInterval(session.duration))
        _selectedDurationMinutes = State(initialValue: Int(session.duration / 60))
    }

    private var isValid: Bool {
        editedEndedAt > editedStartedAt && editedDuration >= 300
    }

    private var calculatedActualDuration: TimeInterval {
        max(0, editedEndedAt.timeIntervalSince(editedStartedAt))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpacing.lg) {
                headerSection
                detailsSection
                reflectionSection
                actionsSection
            }
            .padding(FFSpacing.lg)
        }
        .frame(width: 440)
    }

    private var headerSection: some View {
        PremiumSurface(style: .hero) {
            PremiumSectionHeader(
                "Edit Session",
                eyebrow: "Revision",
                subtitle: "Adjust the project, focus quality, or notes after the fact."
            ) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detailsSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Session Details",
                eyebrow: "Core",
                subtitle: session.startedAt.formatted(date: .abbreviated, time: .shortened) + " \u{00B7} " + session.actualDuration.formattedFocusTime
            )

            timingSection
            projectSection
        }
    }

    private var reflectionSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Reflection",
                eyebrow: "Quality",
                subtitle: "Update how the session felt and what it produced."
            )

            moodSection
            achievementSection
        }
    }

    private var actionsSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Save Changes",
                eyebrow: "Finish",
                subtitle: "Apply the edits and keep your analytics consistent."
            )

            HStack(spacing: FFSpacing.sm) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(FFType.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FFSpacing.sm)
                }
                .buttonStyle(.glass)

                Button {
                    save()
                    dismiss()
                } label: {
                    Text("Save")
                        .font(FFType.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FFSpacing.sm)
                }
                .buttonStyle(.glassProminent)
                .tint(FFColor.focus)
                .disabled(!isValid)
                .opacity(isValid ? 0.8 : 0.5)
            }
        }
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            durationPresetsRow
            datePickersRow
            actualDurationRow

            if !isValid {
                validationWarning
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var durationPresetsRow: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text("Planned Duration")
                .font(FFType.micro)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: FFSpacing.sm) {
                durationPresetButton(mins: 15)
                durationPresetButton(mins: 25)
                durationPresetButton(mins: 45)
                durationPresetButton(mins: 60)
                customDurationButton
            }
        }
    }

    @ViewBuilder
    private func durationPresetButton(mins: Int) -> some View {
        let isSelected = selectedDurationMinutes == mins
        let label = Text("\(mins)m")
            .font(FFType.meta.weight(isSelected ? .semibold : .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.sm)

        if isSelected {
            Button {
                selectedDurationMinutes = mins
                editedDuration = TimeInterval(mins * 60)
                editedEndedAt = editedStartedAt.addingTimeInterval(editedDuration)
            } label: { label }
            .buttonStyle(.glassProminent)
            .tint(FFColor.focus)
        } else {
            Button {
                selectedDurationMinutes = mins
                editedDuration = TimeInterval(mins * 60)
                editedEndedAt = editedStartedAt.addingTimeInterval(editedDuration)
            } label: { label }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var customDurationButton: some View {
        let isCustom = ![15, 25, 45, 60].contains(selectedDurationMinutes)
        let label = Text("Custom")
            .font(FFType.meta.weight(isCustom ? .semibold : .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.sm)

        if isCustom {
            Button {
                selectedDurationMinutes = Int(max(5, editedDuration / 60))
            } label: { label }
            .buttonStyle(.glassProminent)
            .tint(FFColor.focus)
        } else {
            Button {
                selectedDurationMinutes = Int(max(5, editedDuration / 60))
            } label: { label }
            .buttonStyle(.glass)
        }
    }

    private var datePickersRow: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack {
                Text("Start")
                    .font(FFType.meta.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                DatePicker("", selection: $editedStartedAt)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            HStack {
                Text("End")
                    .font(FFType.meta.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                DatePicker("", selection: $editedEndedAt)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
    }

    private var actualDurationRow: some View {
        HStack(spacing: FFSpacing.xs) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text("Actual:")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
            Text(calculatedActualDuration.formattedFocusTime)
                .font(FFType.body.weight(.semibold))
                .monospacedDigit()
            Spacer()
            Text("Planned: \(selectedDurationMinutes)m")
                .font(FFType.meta)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var validationWarning: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
            if editedEndedAt <= editedStartedAt {
                Text("End time must be after start time")
                    .font(.caption)
            } else if editedDuration < 300 {
                Text("Duration must be at least 5 minutes")
                    .font(.caption)
            }
        }
        .foregroundStyle(.orange)
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text("Project")
                .font(FFType.micro)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(1.2)

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
                HStack(spacing: FFSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                            .fill(FFColor.focus.opacity(0.12))

                        Image(systemName: selectedProject?.icon ?? "tag")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FFColor.focus)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedProject == nil ? "Optional categorization" : "Current project")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                        Text(selectedProject?.name ?? "No Project")
                            .font(FFType.body.weight(.medium))
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
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
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("Focus Quality")
                .font(FFType.micro)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: FFSpacing.sm) {
                ForEach(FocusMood.allCases, id: \.self) { mood in
                    moodButton(mood)
                }
            }
        }
    }

    @ViewBuilder
    private func moodButton(_ mood: FocusMood) -> some View {
        let isSelected = selectedMood == mood
        let label = VStack(spacing: FFSpacing.xs) {
            Image(systemName: mood.icon)
                .font(.system(size: 16, weight: .semibold))
            Text(mood.rawValue)
                .font(FFType.meta)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FFSpacing.sm)

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
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text("Achievement")
                .font(FFType.micro)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(1.2)

            TextField("What did you achieve?", text: $achievement)
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
    }

    private func save() {
        session.project = selectedProject
        session.mood = selectedMood
        session.achievement = achievement.isEmpty ? nil : achievement
        session.duration = editedDuration
        session.startedAt = editedStartedAt
        session.endedAt = editedEndedAt
        try? modelContext.save()
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
