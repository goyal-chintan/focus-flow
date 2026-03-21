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
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []
    @State private var saveError: String?
    @State private var durationError: String?

    /// Total allocated in splits (in minutes)
    private var splitsTotalMinutes: Int { splits.reduce(0) { $0 + $1.minutes } }
    private var splitsOverAllocated: Bool { showSplits && splits.count > 1 && splitsTotalMinutes > max(5, duration) }
    private var canSave: Bool { duration >= 5 && !splitsOverAllocated }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
                LiquidSectionHeader("Log Focus Session", subtitle: "Record work completed outside the active timer")

                projectSection
                durationSection
                whenSection
                moodSection
                achievementSection
                splitSection
                actionButtons
            }
            .padding(20)
        }
        .frame(width: 420)
        .background(.background)
        .saveErrorOverlay($saveError)
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

            DurationPresetRow(
                presets: [15, 25, 45, 60],
                selectedMinutes: $duration
            )

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

                Text("minutes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .onChange(of: duration) {
                startTime = Date().addingTimeInterval(TimeInterval(-max(5, duration) * 60))
                durationError = duration < 5 ? "Minimum duration is 5 minutes" : nil
            }

            if let durationError {
                Label(durationError, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .animation(FFMotion.control, value: durationError)
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

            MoodSelector(selectedMood: $selectedMood)
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

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSplits.toggle()
                    if showSplits && splits.isEmpty {
                        splits = [TimeSplitView.SplitEntry(
                            project: selectedProject,
                            minutes: max(1, duration)
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
                    totalDuration: TimeInterval(max(5, duration) * 60),
                    splits: $splits
                )
                .transition(.move(edge: .top).combined(with: .opacity))

                // Split total validation
                if splits.count > 1 {
                    let totalMin = max(5, duration)
                    let allocatedMin = splitsTotalMinutes
                    let allocationLabel = allocatedMin == totalMin
                        ? "✓ \(allocatedMin) of \(totalMin) min allocated"
                        : "\(allocatedMin) of \(totalMin) min allocated"
                    Label(allocationLabel, systemImage: splitsOverAllocated ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(splitsOverAllocated ? Color.orange : Color.green)
                        .animation(FFMotion.control, value: allocatedMin)
                }
            }
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
            .disabled(!canSave)
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

        // Save splits — skip zero/negative duration entries to prevent stat corruption
        if showSplits && splits.count > 1 {
            for entry in splits {
                let splitSeconds = TimeInterval(entry.minutes * 60)
                guard splitSeconds > 0 else { continue }
                let timeSplit = TimeSplit(
                    project: entry.project,
                    customLabel: entry.customLabel.isEmpty ? nil : entry.customLabel,
                    duration: splitSeconds
                )
                timeSplit.session = session
                modelContext.insert(timeSplit)
            }
        }

        saveWithFeedback(modelContext, errorBinding: $saveError)
    }
}

