import SwiftUI
import SwiftData

/// Goals: every active goal with its pace first, then the daily focus time, then the direction behind
/// them (Dan Koe's protocol) (priorities-goals design §3.2, §3.5; screen audit: levers live in
/// key-result captions here). Goals clarity 2026-11-02: what you're working toward comes first;
/// the daily focus time is a setting, so it sits below, folded to one line.
struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.companionNowOverride) private var nowOverride
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @Query private var allSettings: [AppSettings]

    @State private var goalSheet: GoalSheet?
    @State private var showFinished = false
    @State private var pickerProject: PickerTarget?

    private struct PickerTarget: Identifiable {
        let id = UUID()
        let projectID: UUID
        let goalID: UUID
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: nowOverride ?? context.date)
        }
        .sheet(item: $goalSheet) { sheet in GoalFormView(goal: sheet.goal, defaultProjectID: sheet.projectID) }
        .sheet(item: $pickerProject) { target in GoalTaskPickerSheet(projectID: target.projectID, goalID: target.goalID) }
    }

    private var activeGoals: [ProjectGoal] {
        goals.filter { $0.status == .active }.sorted { lhs, rhs in
            if lhs.isBossFight != rhs.isBossFight { return lhs.isBossFight }
            return lhs.deadline < rhs.deadline
        }
    }

    private var finishedGoals: [ProjectGoal] {
        goals.filter { $0.status != .active }.sorted { ($0.completedAt ?? $0.deadline) > ($1.completedAt ?? $1.deadline) }
    }

    private func content(now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("Goals", subtitle: activeGoals.isEmpty
                             ? "Something you want done by a date, and the numbers that prove it."
                             : "\(activeGoals.count) active · each one says whether you're on pace and what keeps you there") {
                    Button {
                        goalSheet = GoalSheet(goal: nil, projectID: projects.first { $0.priorityRank == 1 }?.id)
                    } label: {
                        Label("New Goal", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                // Goal cards first; their captions carry today's pace ("1 a day finishes on time"),
                // so levers are not repeated here (screen audit: levers once per screen).
                if activeGoals.isEmpty {
                    FFSection {
                        VStack(alignment: .leading, spacing: FFSpace.m) {
                            FFEmptyState(
                                systemImage: "scope",
                                message: "No goals yet",
                                detail: "A goal is a date and a number: “60 LeetCode questions by 28 Nov”. Each day the app tells you if you're on pace and how many to do."
                            )
                            Button("New Goal") {
                                goalSheet = GoalSheet(goal: nil, projectID: projects.first { $0.priorityRank == 1 }?.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ForEach(activeGoals) { goal in
                        GoalCard(
                            goal: goal,
                            project: projects.first { $0.id == goal.projectID },
                            now: now,
                            onEdit: { goalSheet = GoalSheet(goal: goal, projectID: goal.projectID) },
                            // Only for a project that syncs a Reminders list: the button says "Reminders".
                            onPickReminders: projects.first(where: { $0.id == goal.projectID && !($0.reminderListID ?? "").isEmpty })
                                .map { project in { pickerProject = PickerTarget(projectID: project.id, goalID: goal.id) } }
                        )
                    }
                }

                // The one daily goal, set here only (it used to live in Settings and onboarding too).
                if let settings = allSettings.first {
                    DailyGoalCard(settings: settings, projects: projects, now: now)
                    DirectionCard(settings: settings)
                }

                if !finishedGoals.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(FFAnimation.control) { showFinished.toggle() }
                        } label: {
                            HStack(spacing: FFSpace.s) {
                                Text("Finished (\(finishedGoals.count))").ffText(.headline)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(showFinished ? 90 : 0))
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(showFinished ? "Hide finished goals" : "Show finished goals")
                        if showFinished {
                        VStack(spacing: FFSpace.s) {
                            ForEach(finishedGoals) { goal in
                                HStack {
                                    Image(systemName: goal.status == .done ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundStyle(goal.status == .done ? FFPalette.goal : .secondary)
                                    Text(goal.title).ffText(.body)
                                    Spacer()
                                    Text((goal.completedAt ?? goal.deadline).formatted(.dateTime.day().month(.abbreviated))).ffText(.caption)
                                    Button("Open") { goalSheet = GoalSheet(goal: goal, projectID: goal.projectID) }
                                        .buttonStyle(.link)
                                }
                                .padding(.horizontal, FFSpace.s)
                                .frame(minHeight: 30)
                            }
                        }
                        .padding(.top, FFSpace.s)
                        }
                    }
                    .padding(FFSpace.l)
                    .ffSurface()
                }
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Dan Koe's "fix your life" outputs, kept one click away: anti-vision (the stakes), vision (the
/// win condition), the 1-year goal and the rules. Collapsed to the 1-year goal; the boss fight is
/// badged on its goal card.
struct DirectionCard: View {
    @Bindable var settings: AppSettings

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var editing = false

    private struct Field: Identifiable {
        let id: String
        let title: String
        let prompt: String
        let symbol: String
        let tint: Color
        let keyPath: ReferenceWritableKeyPath<AppSettings, String?>
    }

    private var fields: [Field] {
        [
            Field(id: "anti", title: "Anti-vision", prompt: "The life I refuse to live: an ordinary Tuesday five years from now if nothing changes.", symbol: "xmark.octagon.fill", tint: FFPalette.destructive, keyPath: \.lifeAntiVision),
            Field(id: "vision", title: "Vision", prompt: "An ordinary Tuesday three years from now, if this goes right.", symbol: "sparkles", tint: FFPalette.goal, keyPath: \.lifeVision),
            Field(id: "year", title: "1-year goal", prompt: "What must be true in a year to know the old pattern is broken?", symbol: "mountain.2.fill", tint: FFPalette.accent, keyPath: \.lifeYearGoal),
            Field(id: "rules", title: "Rules", prompt: "What I won't trade away (sleep, family) and the limits I set myself.", symbol: "list.bullet.rectangle", tint: .secondary, keyPath: \.lifeConstraints),
        ]
    }

    private var yearGoal: String {
        let value = settings.lifeYearGoal?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "not set yet" : value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            Button {
                if expanded && editing { try? modelContext.save(); editing = false }
                withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) { expanded.toggle() }
            } label: {
                HStack(spacing: FFSpace.s) {
                    Image(systemName: "mountain.2.fill")
                        .foregroundStyle(FFPalette.accent)
                        .accessibilityHidden(true)
                    Text("1-year:").ffText(.callout)
                    Text(yearGoal).ffText(.headline).truncationMode(.tail)
                    Spacer(minLength: FFSpace.s)
                    Text("Direction").ffText(.callout)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .lineLimit(1)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Direction. 1-year goal: \(yearGoal)")
            .accessibilityHint(expanded ? "Collapse" : "Show anti-vision, vision and rules")

            if expanded {
                HStack(alignment: .firstTextBaseline) {
                    Text("What you're playing for, and what you refuse to become.").ffText(.callout)
                    Spacer()
                    Button(editing ? "Done" : "Edit") {
                        if editing { try? modelContext.save() }
                        withAnimation(FFAnimation.control) { editing.toggle() }
                    }
                    .buttonStyle(.bordered)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: FFSpace.m), GridItem(.flexible(), spacing: FFSpace.m)], spacing: FFSpace.m) {
                    ForEach(fields) { field in
                        fieldView(field)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, FFSpace.l)
        .padding(.vertical, FFSpace.m)
        .ffSurface()
        .help("From Dan Koe's \"How to fix your entire life in 1 day\" (2026): anti-vision, vision, 1-year goal, 1-month project, daily levers, constraints.")
    }

    @ViewBuilder
    private func fieldView(_ field: Field) -> some View {
        let value = settings[keyPath: field.keyPath] ?? ""
        VStack(alignment: .leading, spacing: 6) {
            Label(field.title, systemImage: field.symbol)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(field.tint)
            if editing {
                TextField(field.prompt, text: Binding(
                    get: { settings[keyPath: field.keyPath] ?? "" },
                    set: { settings[keyPath: field.keyPath] = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            } else {
                Text(value.isEmpty ? field.prompt : value)
                    .ffText(value.isEmpty ? .caption : .body)
                    .italic(value.isEmpty)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(FFSpace.m)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous).fill(field.tint.opacity(0.06)))
    }
}
