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
    @State private var saveError: String?
    @State private var showDeleteConfirm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    @Query private var allSettings: [AppSettings]
    private var settings: AppSettings? { allSettings.first }

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
        .saveErrorOverlay($saveError)
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
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
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
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    private var durationPresetsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Planned Duration")

            DurationPresetRow(
                presets: [15, 25, 45, 60],
                selectedMinutes: $selectedDurationMinutes
            )
            .onChange(of: selectedDurationMinutes) {
                editedDuration = TimeInterval(selectedDurationMinutes * 60)
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

            MoodSelector(selectedMood: $selectedMood)
        }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Achievement")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $achievement)
                    .font(.system(size: 13, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)

                if achievement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Log your wins — one per line...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 94, maxHeight: 170)
            .padding(2)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))

            if !achievement.isEmpty {
                let items = achievement.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.top, 2)
                            Text(item.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.3, dampingFraction: 0.8)) {
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
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSplits {
                TimeSplitView(
                    totalDuration: calculatedActualDuration,
                    splits: $splits
                )
                .transition(.opacity)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: LiquidDesignTokens.Spacing.small) {
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

            Button {
                showDeleteConfirm = true
            } label: {
                Label("Delete Session", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete this session permanently")
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This session will be permanently deleted and cannot be recovered.")
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

        saveWithFeedback(modelContext, errorBinding: $saveError)
        // Refresh the menu-bar today-total in case duration or date changed.
        NotificationCenter.default.post(name: .focusSessionLoggedManually, object: nil)
        // Keep Calendar in sync: update existing event or create one if missing.
        if settings?.calendarIntegrationEnabled == true {
            let calName = settings?.calendarName ?? "FocusFlow"
            let calId = settings?.selectedCalendarId ?? ""
            if let existingId = session.calendarEventId {
                CalendarService.shared.updateEvent(
                    eventId: existingId,
                    title: session.label,
                    notes: session.achievement,
                    startDate: editedStartedAt,
                    endDate: editedEndedAt
                )
            } else {
                let eventId = CalendarService.shared.createEvent(
                    title: session.label,
                    startDate: editedStartedAt,
                    endDate: editedEndedAt,
                    notes: session.achievement,
                    calendarName: calName,
                    calendarId: calId.isEmpty ? nil : calId
                )
                if let eventId {
                    session.calendarEventId = eventId
                    saveWithFeedback(modelContext, errorBinding: $saveError)
                }
            }
        }
    }

    private func deleteSession() {
        // Remove the associated Calendar event if one was created.
        if let eventId = session.calendarEventId {
            CalendarService.shared.deleteEvent(eventId: eventId)
        }
        for split in session.splits {
            modelContext.delete(split)
        }
        modelContext.delete(session)
        saveWithFeedback(modelContext, errorBinding: $saveError)
        dismiss()
    }

}
