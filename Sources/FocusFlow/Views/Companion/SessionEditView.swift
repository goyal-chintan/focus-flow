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
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []

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

        // Pre-populate splits from existing session data
        if !session.splits.isEmpty {
            let entries = session.splits.map { split in
                TimeSplitView.SplitEntry(
                    project: split.project,
                    customLabel: split.customLabel ?? "",
                    minutes: max(1, Int(split.duration / 60))
                )
            }
            _splits = State(initialValue: entries)
            _showSplits = State(initialValue: true)
        }
    }

    private var isValid: Bool {
        editedEndedAt > editedStartedAt && editedDuration >= 300
    }

    private var calculatedActualDuration: TimeInterval {
        max(0, editedEndedAt.timeIntervalSince(editedStartedAt))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
                headerSection
                timingSection
                projectSection
                moodSection
                achievementSection
                splitSection
                actionsSection
            }
            .padding(20)
        }
        .frame(width: 420)
        .background(.background)
    }

    private var headerSection: some View {
        LiquidSectionHeader(
            "Edit Session",
            subtitle: session.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        ) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            sectionLabel("Timing")
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
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Planned Duration")

            HStack(spacing: 6) {
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
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

        if isSelected {
            Button {
                selectedDurationMinutes = mins
                editedDuration = TimeInterval(mins * 60)
            } label: {
                label
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .buttonBorderShape(.capsule)
        } else {
            Button {
                selectedDurationMinutes = mins
                editedDuration = TimeInterval(mins * 60)
            } label: {
                label
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
    }

    private var customDurationButton: some View {
        let isCustom = ![15, 25, 45, 60].contains(selectedDurationMinutes)
        let label = Text("Custom")
            .font(.system(size: 11, weight: isCustom ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

        return Group {
            if isCustom {
                Button {} label: { label }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .buttonBorderShape(.capsule)
            } else {
                Button {
                    selectedDurationMinutes = Int(editedDuration / 60)
                } label: {
                    label
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private var datePickersRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Start")
                    .frame(width: 40, alignment: .leading)
                DatePicker("", selection: $editedStartedAt)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            HStack {
                sectionLabel("End")
                    .frame(width: 40, alignment: .leading)
                DatePicker("", selection: $editedEndedAt)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
    }

    private var actualDurationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text("Actual")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(calculatedActualDuration.formattedFocusTime)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()

            Spacer()

            Text("Planned: \(selectedDurationMinutes)m")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var validationWarning: some View {
        HStack(spacing: 6) {
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

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Focus Quality")

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
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)

        if isSelected {
            Button { selectedMood = nil } label: { label }
                .buttonStyle(.glassProminent)
                .tint(moodColor(mood))
                .buttonBorderShape(.roundedRectangle(radius: 12))
        } else {
            Button { selectedMood = mood } label: { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 12))
        }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Achievement")

            TextField("What did you achieve?", text: $achievement)
                .textFieldStyle(.plain)
                .padding(8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSplits.toggle()
                    if showSplits && splits.isEmpty {
                        splits = [TimeSplitView.SplitEntry(
                            project: selectedProject,
                            minutes: max(1, Int(calculatedActualDuration / 60))
                        )]
                    }
                }
            } label: {
                HStack {
                    Image(systemName: showSplits ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                        .font(.caption)
                    Text("Split time across projects")
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
                    totalDuration: calculatedActualDuration,
                    splits: $splits
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: LiquidDesignTokens.Spacing.medium) {
            LiquidActionButton(
                title: "Cancel",
                icon: "xmark",
                role: .secondary
            ) {
                dismiss()
            }

            LiquidActionButton(
                title: "Save",
                icon: "checkmark",
                role: .primary
            ) {
                save()
                dismiss()
            }
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.55)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func save() {
        session.project = selectedProject
        session.mood = selectedMood
        session.achievement = achievement.isEmpty ? nil : achievement
        session.duration = editedDuration
        session.startedAt = editedStartedAt
        session.endedAt = editedEndedAt

        // Update splits: clear existing, insert new ones if split mode active
        for existing in session.splits {
            modelContext.delete(existing)
        }
        session.splits = []

        if showSplits && splits.count > 1 {
            for entry in splits {
                let timeSplit = TimeSplit(
                    project: entry.project,
                    customLabel: entry.customLabel.isEmpty ? nil : entry.customLabel,
                    duration: TimeInterval(entry.minutes * 60)
                )
                timeSplit.session = session
                modelContext.insert(timeSplit)
            }
        }

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
