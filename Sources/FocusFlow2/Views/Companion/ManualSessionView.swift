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
            VStack(alignment: .leading, spacing: FFSpacing.lg) {
                headerSection
                detailsSection
                reflectionSection
                actionsSection
            }
            .padding(FFSpacing.lg)
        }
        .frame(width: 460)
    }

    private var headerSection: some View {
        PremiumSurface(style: .hero) {
            PremiumSectionHeader(
                "Log Focus Session",
                eyebrow: "Manual Entry",
                subtitle: "Capture a completed session with the same premium metadata as live focus."
            )
        }
    }

    private var detailsSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Session Details",
                eyebrow: "Core",
                subtitle: "Assign the project, duration, and timestamp."
            )

            projectSection
            durationSection
            whenSection
        }
    }

    private var reflectionSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Reflection",
                eyebrow: "Quality",
                subtitle: "Optional, but useful for learning what deep work looks like for you."
            )

            moodSection
            achievementSection
        }
    }

    private var actionsSection: some View {
        PremiumSurface(style: .card) {
            PremiumSectionHeader(
                "Save Session",
                eyebrow: "Finish",
                subtitle: "Store the entry and include it in your daily and weekly stats."
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
                    Text("Log Session")
                        .font(FFType.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FFSpacing.sm)
                }
                .buttonStyle(.glassProminent)
                .tint(FFColor.focus)
                .disabled(duration < 5)
            }
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
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
                selectionField(
                    title: selectedProject?.name ?? "No Project",
                    subtitle: selectedProject == nil ? "Optional categorization" : "Current project",
                    icon: selectedProject?.icon ?? "tag"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var durationPresets: some View {
        HStack(spacing: FFSpacing.sm) {
            ForEach([15, 25, 45, 60], id: \.self) { mins in
                DurationPresetButton(mins: mins, isSelected: duration == mins) {
                    duration = mins
                    startTime = Date().addingTimeInterval(TimeInterval(-mins * 60))
                }
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            sectionLabel("Duration")

            durationPresets

            PremiumSurface(style: .inset) {
                HStack(spacing: FFSpacing.sm) {
                    Text("Custom duration")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)

                    Spacer()

                    TextField("min", value: $duration, format: .number)
                        .textFieldStyle(.plain)
                        .font(FFType.body)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .padding(.horizontal, FFSpacing.sm)
                        .padding(.vertical, FFSpacing.xs)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous))
                        .onChange(of: duration) {
                            startTime = Date().addingTimeInterval(TimeInterval(-max(5, duration) * 60))
                        }

                    Text("min")
                        .font(FFType.meta)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            sectionLabel("When")

            PremiumSurface(style: .inset) {
                DatePicker("Started at", selection: $startTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            sectionLabel("Focus Quality")

            HStack(spacing: FFSpacing.sm) {
                ForEach(FocusMood.allCases, id: \.self) { mood in
                    MoodButton(mood: mood, isSelected: selectedMood == mood) {
                        selectedMood = selectedMood == mood ? nil : mood
                    }
                }
            }
        }
    }

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            sectionLabel("What did you achieve?")
            TextField("e.g. Finished the API integration", text: $achievement)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(FFType.micro)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(1.2)
    }

    private func selectionField(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: FFSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                    .fill(FFColor.focus.opacity(0.12))

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FFColor.focus)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                Text(title)
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
                Text("\(mins) min")
                    .font(FFType.meta.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FFSpacing.sm)
            }
            .buttonStyle(.glassProminent)
            .tint(FFColor.focus)
        } else {
            Button(action: action) {
                Text("\(mins) min")
                    .font(FFType.meta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FFSpacing.sm)
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
        VStack(spacing: FFSpacing.xs) {
            Image(systemName: mood.icon)
                .font(.system(size: 16, weight: .semibold))
            Text(mood.rawValue)
                .font(FFType.meta)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FFSpacing.sm)
    }

    private var moodColor: Color {
        switch mood {
        case .distracted: FFColor.warning
        case .neutral: .secondary
        case .focused: FFColor.focus
        case .deepFocus: FFColor.deepFocus
        }
    }
}
