import SwiftData
import SwiftUI

/// Pick a project's reminders and tasks into a goal (2026-11-02). Every reminder in the project's
/// list is one of its tasks (today's, or on its later due day), so the list here is the whole
/// list: tick several, a whole day, or Select All, and each one counts 1 toward the goal's number.
/// Opened from a goal card ("Add from Reminders…") or a project's tasks ("Add to a Goal…").
struct GoalTaskPickerSheet: View {
    let projectID: UUID
    var goalID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(TimerViewModel.self) private var timerVM
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]
    @Query private var tasks: [DailyTask]

    @State private var chosenGoalID: UUID?
    /// nil: a new number.
    @State private var chosenResultID: UUID?
    @State private var newTitle = "Steps"
    @State private var raiseTarget = true
    @State private var picked: Set<UUID> = []
    @State private var didSetDefaults = false

    init(projectID: UUID, goalID: UUID? = nil, now: Date = Date()) {
        self.projectID = projectID
        self.goalID = goalID
        let start = Calendar.current.startOfDay(for: now)
        _tasks = Query(filter: #Predicate<DailyTask> { $0.day >= start && $0.projectID == projectID && !$0.isDone },
                       sort: [SortDescriptor(\DailyTask.day), SortDescriptor(\DailyTask.order)])
    }

    private var project: Project? { projects.first { $0.id == projectID } }
    private var projectGoals: [ProjectGoal] { goals.filter { $0.projectID == projectID && $0.status == .active } }
    private var goal: ProjectGoal? { projectGoals.first { $0.id == chosenGoalID } }
    private var numbers: [GoalKeyResult] { goal?.sortedKeyResults.filter { $0.kind == .count } ?? [] }
    private var todays: [DailyTask] { tasks.filter { Calendar.current.isDateInToday($0.day) } }
    private var later: [DailyTask] { tasks.filter { !Calendar.current.isDateInToday($0.day) } }
    /// Already counting toward the chosen number: shown ticked, not picked again.
    private func counts(_ task: DailyTask) -> Bool { chosenResultID != nil && task.keyResultID == chosenResultID }
    private var pickable: [DailyTask] { tasks.filter { !counts($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add reminders to a goal").ffText(.title3)
                Text("Pick what makes up the goal. Each one done, here or in Reminders, adds 1 to its number.")
                    .ffText(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top], FFSpace.xl)
            .padding(.bottom, FFSpace.l)

            if projectGoals.isEmpty {
                FFEmptyState(
                    systemImage: "scope",
                    message: "\(project?.name ?? "This project") has no goal yet",
                    detail: "Add a goal on the project's page first, then pick its reminders here."
                )
                .padding(.horizontal, FFSpace.xl)
                Spacer(minLength: 0)
            } else {
                targetFields
                    .padding(.horizontal, FFSpace.xl)
                Divider().padding(.top, FFSpace.l)
                taskList
            }

            Divider()
            footer
        }
        .frame(width: 600, height: 640)
        .onAppear(perform: setDefaults)
        .onChange(of: chosenGoalID) { _, _ in
            chosenResultID = numbers.first?.id
        }
    }

    // MARK: Where they count

    private var targetFields: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            HStack(alignment: .top, spacing: FFSpace.l) {
                field("Goal") {
                    Picker("Goal", selection: $chosenGoalID) {
                        ForEach(projectGoals) { goal in
                            Text(goal.title).tag(Optional(goal.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }
                field("Counts toward") {
                    Picker("Counts toward", selection: $chosenResultID) {
                        ForEach(numbers) { number in
                            Text("\(number.title) (target \(GoalPlainLanguage.number(number.target)))").tag(Optional(number.id))
                        }
                        if !numbers.isEmpty { Divider() }
                        Text("A new number").tag(UUID?.none)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                }
            }
            if chosenResultID == nil {
                field("Name of the new number") {
                    TextField("Steps", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                Text("Its target is how many you pick: \(picked.count) now, and it grows when you add more later.")
                    .ffText(.caption)
            } else {
                Toggle(isOn: $raiseTarget) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Raise its target by the ones you pick").ffText(.body)
                        Text("Off: they count toward the target it already has.").ffText(.caption)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    // MARK: The list

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                if tasks.isEmpty {
                    FFEmptyState(
                        systemImage: "checklist",
                        message: "No open tasks or reminders in \(project?.name ?? "this project")",
                        detail: "Link a Reminders list on the project's page and its reminders appear here."
                    )
                } else {
                    HStack {
                        Text("\(picked.count) picked").ffText(.callout).monospacedDigit()
                        Spacer()
                        selectAllButton(pickable, label: "Select All")
                    }
                    group("Today", todays)
                    group("Later", later)
                }
            }
            .padding(FFSpace.xl)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [DailyTask]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(title) · \(items.count)").ffText(.headline)
                    Spacer()
                    selectAllButton(items.filter { !counts($0) }, label: "Select \(title)")
                }
                .padding(.bottom, FFSpace.xs)
                ForEach(items) { task in row(task) }
            }
        }
    }

    private func selectAllButton(_ items: [DailyTask], label: String) -> some View {
        let ids = Set(items.map(\.id))
        let all = !ids.isEmpty && ids.isSubset(of: picked)
        return Button(all ? "Deselect" : label) {
            if all { picked.subtract(ids) } else { picked.formUnion(ids) }
        }
        .buttonStyle(.borderless)
        .disabled(ids.isEmpty)
    }

    /// The whole row toggles.
    private func row(_ task: DailyTask) -> some View {
        let already = counts(task)
        let isOn = already || picked.contains(task.id)
        let elsewhere = !already ? task.keyResultID.flatMap { id in goals.flatMap(\.keyResults).first { $0.id == id } } : nil
        return Button {
            if picked.contains(task.id) { picked.remove(task.id) } else { picked.insert(task.id) }
        } label: {
            HStack(spacing: FFSpace.s) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn ? FFPalette.accent : Color.secondary)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(task.title).ffText(.body).lineLimit(2).multilineTextAlignment(.leading)
                        if task.reminderID != nil {
                            Image(systemName: "checklist")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("From Reminders")
                        }
                    }
                    if already {
                        Text("Already counts toward this").ffText(.caption)
                    } else if let elsewhere {
                        Text("Counts toward \(elsewhere.title) now; picking it moves it here").ffText(.caption)
                    }
                }
                Spacer(minLength: FFSpace.s)
                if !Calendar.current.isDateInToday(task.day) {
                    Text(ProjectRemindersPanel.dueLabel(task.day)).ffText(.caption).monospacedDigit()
                }
            }
            .padding(.horizontal, FFSpace.xs)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(already)
        .ffHoverRow(isSelected: picked.contains(task.id))
        .accessibilityLabel(task.title)
        .accessibilityValue(isOn ? "Picked" : "Not picked")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: FFSpace.s) {
            if let goal, !picked.isEmpty {
                Text("Adds \(picked.count) to \(chosenResultID.flatMap { id in numbers.first { $0.id == id }?.title } ?? newTitle) · \(goal.title)")
                    .ffText(.caption)
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(picked.isEmpty ? "Add" : "Add \(picked.count)") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(picked.isEmpty || goal == nil)
        }
        .padding(FFSpace.l)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func setDefaults() {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        chosenGoalID = goalID ?? projectGoals.first(where: \.isBossFight)?.id ?? projectGoals.first?.id
        chosenResultID = numbers.first?.id
    }

    private func save() {
        guard let goal else { return }
        let chosen = tasks.filter { picked.contains($0.id) }
        timerVM.countTasks(chosen, toward: goal, resultID: chosenResultID, newTitle: newTitle, raiseTarget: raiseTarget)
        dismiss()
    }
}
