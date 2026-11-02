import SwiftUI
import SwiftData

// Daily tasks (daily tasks design: docs/plans/2026-10-28-daily-tasks-design.md).

/// A round tick that fills with the tint and springs when checked.
struct DailyTaskCheck: View {
    let isDone: Bool
    var tint: Color = FFPalette.goal
    var size: CGFloat = 18
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? tint : Color.secondary.opacity(0.5), lineWidth: 1.5)
                Circle()
                    .fill(tint)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .opacity(isDone ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isDone ? 1 : 0.4)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: size, height: size)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isDone)
        .accessibilityLabel(isDone ? "Mark not done" : "Mark done")
    }
}

/// A counted task's control: a ring that fills with each +1, a plus inside. Done shows the tick.
struct DailyTaskCounterButton: View {
    let logged: Double
    let target: Double
    var tint: Color = FFPalette.goal
    var size: CGFloat = 18
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { target > 0 ? min(1, logged / target) : 0 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(0.75)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: fraction)
        .accessibilityLabel("Add one")
        .accessibilityValue("\(DailyTaskReceipt.number(logged)) of \(DailyTaskReceipt.number(target))")
    }
}

/// The one control every task row uses (Today, popover, block-end): +1 on an open counted task,
/// a tick otherwise. The help text says what a tap will log, so nothing happens by surprise.
struct DailyTaskControl: View {
    let task: DailyTask
    var resultTitle: String? = nil
    var size: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Group {
            if task.isCounted, !task.isDone {
                DailyTaskCounterButton(logged: task.loggedCount, target: task.progressAmount, size: size, action: action)
            } else {
                DailyTaskCheck(isDone: task.isDone, size: size, action: action)
            }
        }
        .help(Self.help(task, resultTitle: resultTitle))
    }

    /// "Add 1 to Problems solved (1 of 3 today)", "Mark done · adds 1 to SQL", "Mark done".
    static func help(_ task: DailyTask, resultTitle: String?) -> String {
        if task.isDone { return "Done. Click to mark not done\(resultTitle.map { " (takes back what it logged to \($0))" } ?? "")." }
        if task.isCounted {
            return "Add 1 to \(resultTitle ?? "the goal") (\(DailyTaskReceipt.number(task.loggedCount)) of \(DailyTaskReceipt.number(task.progressAmount)) today)"
        }
        if let resultTitle { return "Mark done · adds \(DailyTaskReceipt.number(task.progressAmount)) to \(resultTitle)" }
        return "Mark done"
    }
}

/// "1 of 3" beside a counted task's title.
struct DailyTaskCountText: View {
    let task: DailyTask

    var body: some View {
        if task.isCounted {
            Text("\(DailyTaskReceipt.number(task.loggedCount)) of \(DailyTaskReceipt.number(task.progressAmount))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(task.isDone ? FFPalette.goal : FFPalette.accent)
                .contentTransition(.numericText())
                .padding(.horizontal, 7)
                .frame(minHeight: 20)
                .background(Capsule().fill((task.isDone ? FFPalette.goal : FFPalette.accent).opacity(0.12)))
                .accessibilityLabel("\(DailyTaskReceipt.number(task.loggedCount)) of \(DailyTaskReceipt.number(task.progressAmount)) today")
        }
    }
}

/// "+1 Problems solved · today 2 of 3 · goal 12 of 40   Undo" for a few seconds after a tap.
struct DailyTaskReceiptBanner: View {
    /// Only receipts for these tasks (nil: any).
    var taskIDs: Set<UUID>? = nil
    var compact = false

    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let receipt = timerVM.dailyTaskReceipt.flatMap { r in (taskIDs?.contains(r.taskID) ?? true) ? r : nil }
        ZStack {
            if let receipt {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(FFPalette.goal)
                        .accessibilityHidden(true)
                    Text(receipt.text)
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Undo") {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { timerVM.undoDailyTaskReceipt() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(FFPalette.accent)
                    .frame(minHeight: 26)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Undo: \(receipt.text)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(FFPalette.goal.opacity(0.1)))
                .transition(.opacity.combined(with: .move(edge: .top)))
                .id(receipt.id)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: receipt?.id)
    }
}

/// One task: tick, title, where it counts, and a menu.
struct DailyTaskRow: View {
    let task: DailyTask
    let project: Project?
    let resultTitle: String?
    /// The control's tap: +1 on an open counted task, tick or untick otherwise.
    let onToggle: () -> Void
    var onStepDown: (() -> Void)?
    var onMarkDone: (() -> Void)?
    var onTop: (() -> Void)?
    var onTomorrow: (() -> Void)?
    var onDelete: (() -> Void)?
    /// The task mirrors a reminder in a list its project still syncs: delete removes both, so it asks.
    var syncsReminder = false
    /// Count key results a task can count toward ("LeetCode · Interview-ready"), for "Link to goal".
    var goalOptions: [(id: UUID, title: String)] = []
    var onLink: ((UUID?) -> Void)?
    var onRename: ((String) -> Void)?
    /// Off on a project's own page, where every row is that project's.
    var showsProject = true

    @State private var hovering = false
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var renameText = ""

    private func requestDelete() {
        if syncsReminder { confirmDelete = true } else { onDelete?() }
    }

    var body: some View {
        HStack(spacing: FFSpace.s) {
            DailyTaskControl(task: task, resultTitle: resultTitle, action: onToggle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: FFSpace.s) {
                    Text(task.title)
                        .ffText(.body)
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(2)
                    DailyTaskCountText(task: task)
                    if syncsReminder {
                        Image(systemName: "checklist")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .help("Synced with Reminders")
                            .accessibilityLabel("Synced with Reminders")
                    }
                }
                if (showsProject && project != nil) || resultTitle != nil || task.carriedFromID != nil {
                    HStack(spacing: FFSpace.s) {
                        if showsProject, let project {
                            HStack(spacing: 4) {
                                Circle().fill(FFPalette.project(project.color)).frame(width: 6, height: 6)
                                Text(project.name)
                            }
                        }
                        if let resultTitle {
                            Label(SessionTasksSection.goalCaption(task, resultTitle: resultTitle), systemImage: "target")
                                .labelStyle(.titleAndIcon)
                        }
                        if task.carriedFromID != nil {
                            Label("Carried over", systemImage: "arrow.uturn.forward")
                        }
                    }
                    .ffText(.caption)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let onDelete {
                // Always laid out, shown on hover, so rows never shift.
                Button(action: requestDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help(syncsReminder ? "Delete task and its reminder" : "Delete task")
                .accessibilityLabel(syncsReminder ? "Delete task and its reminder" : "Delete task")
            }
        }
        .padding(.horizontal, FFSpace.xs)
        .padding(.vertical, 3)
        .ffHoverRow()
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        .contextMenu {
            if task.isCounted, !task.isDone {
                Button("Add 1", action: onToggle)
                if task.loggedCount > 0, let onStepDown { Button("Take back 1", action: onStepDown) }
                if let onMarkDone { Button("Mark all \(Self.amountText(task.progressAmount)) done", action: onMarkDone) }
            } else {
                Button(task.isDone ? "Mark not done" : "Mark done", action: onToggle)
            }
            if !task.isDone {
                if let onTop { Button("Move to top", action: onTop) }
                if let onTomorrow { Button("Move to tomorrow", action: onTomorrow) }
            }
            Divider()
            if onRename != nil {
                Button("Rename…") {
                    renameText = task.title
                    renaming = true
                }
            }
            if let onLink, !goalOptions.isEmpty {
                // Any task (an imported reminder too) can count toward a goal: ticking it logs progress.
                Menu("Link to goal") {
                    linkButton("Not linked", id: nil, onLink: onLink)
                    Divider()
                    ForEach(goalOptions, id: \.id) { option in
                        linkButton(option.title, id: option.id, onLink: onLink)
                    }
                }
            }
            if onDelete != nil {
                Divider()
                Button(syncsReminder ? "Delete from FocusFlow and Reminders…" : "Delete", role: .destructive, action: requestDelete)
            }
        }
        .alert("Rename task", isPresented: $renaming) {
            TextField("Title", text: $renameText)
            Button("Rename") { onRename?(renameText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if syncsReminder { Text("The reminder is renamed too.") }
        }
        .confirmationDialog("Delete “\(task.title)” from Reminders too?", isPresented: $confirmDelete) {
            Button("Delete from both", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's synced with \(project?.name ?? "this project")'s Reminders list. To keep the reminder, move the task to tomorrow instead.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(task.isDone ? .isSelected : [])
    }

    @ViewBuilder
    private func linkButton(_ title: String, id: UUID?, onLink: @escaping (UUID?) -> Void) -> some View {
        if task.keyResultID == id {
            Button { onLink(id) } label: { Label(title, systemImage: "checkmark") }
        } else {
            Button(title) { onLink(id) }
        }
    }

    static func amountText(_ amount: Double) -> String {
        amount.rounded() == amount ? String(Int(amount)) : String(format: "%.1f", amount)
    }
}

/// Today tab: plan, tick, link to goals, carry over, and the week's planned against done.
/// With `projectID` it is that project's page section (project tasks redesign 2026-11-02): only
/// its tasks and goals, new tasks go to it, and its Reminders list sits underneath.
struct DailyTasksSection: View {
    let now: Date
    var projectID: UUID? = nil

    @Environment(TimerViewModel.self) private var timerVM
    private var remindersOn: Bool { timerVM.remindersSyncOn }
    @Query private var tasks: [DailyTask]
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]

    @State private var draftTitle = ""
    @State private var draftProjectID: UUID?
    @State private var draftResultID: UUID?
    @FocusState private var fieldFocused: Bool

    init(now: Date, projectID: UUID? = nil) {
        self.now = now
        self.projectID = projectID
        _draftProjectID = State(initialValue: projectID)
        let since = Calendar.current.date(byAdding: .day, value: -(DailyTaskPlanner.carryOverLookbackDays + 1), to: Calendar.current.startOfDay(for: now)) ?? now
        _tasks = Query(filter: #Predicate<DailyTask> { $0.day >= since })
    }

    private var scoped: [DailyTask] { projectID == nil ? tasks : DailyTaskPlanner.forProject(tasks, projectID) }
    private var todays: [DailyTask] { DailyTaskPlanner.tasks(scoped, on: now) }
    private var stats: DailyTaskStats { DailyTaskPlanner.stats(scoped, on: now) }
    private var activeGoals: [ProjectGoal] {
        goals.filter { $0.status == .active && (projectID == nil || $0.projectID == projectID) }
    }
    private var scopedProject: Project? { projectID.flatMap { id in projects.first { $0.id == id } } }
    /// Count key results only: a goal is measured in numbers; one-off steps are tasks.
    private var keyResults: [(result: GoalKeyResult, goal: ProjectGoal)] {
        activeGoals.flatMap { goal in goal.sortedKeyResults.filter { $0.kind == .count }.map { ($0, goal) } }
    }

    /// The numbers a task on `projectID` can count toward: its project's goals only (2026-11-02:
    /// with Office picked, the menu offered Learning's goals). With no project, every goal.
    private func keyResults(for projectID: UUID?) -> [(result: GoalKeyResult, goal: ProjectGoal)] {
        guard let projectID else { return keyResults }
        return keyResults.filter { $0.goal.projectID == projectID }
    }

    var body: some View {
        let history = DailyTaskPlanner.history(tasks, endingOn: now)
        FFSection("Today's tasks",
                  subtitle: projectID == nil
                    ? "Tick what you finish. A task linked to a goal has a counter: each + logs 1 to the goal."
                    : "What you'll do for \(scopedProject?.name ?? "this project") today. Tick what you finish.") {
            if stats.planned > 0 {
                DailyTaskProgressBadge(stats: stats)
            }
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.m) {
                if projectID == nil { carryOverBanner }
                addRow
                suggestions
                DailyTaskReceiptBanner()
                list
                if let project = scopedProject {
                    Divider().padding(.vertical, FFSpace.xs)
                    ProjectRemindersPanel(project: project)
                } else if history.filter({ $0.planned > 0 }).count >= 2 {
                    // Follow-through needs a little history before it says anything.
                    Divider().padding(.vertical, FFSpace.xs)
                    DailyTaskWeekStrip(history: history)
                }
            }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var carryOverBanner: some View {
        let carry = DailyTaskPlanner.carryOverCandidates(tasks, today: now)
        if let first = carry.first {
            HStack(spacing: FFSpace.s) {
                Image(systemName: "arrow.uturn.forward.circle.fill").foregroundStyle(FFPalette.atRisk)
                Text("\(carry.count) unfinished from \(first.day.formatted(.dateTime.weekday(.wide))): \(carry.prefix(2).map(\.title).joined(separator: ", "))\(carry.count > 2 ? "…" : "")")
                    .ffText(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(carry.count == 1 ? "Bring it over" : "Bring them over") {
                    withAnimation(.smooth(duration: 0.3)) { _ = timerVM.carryOverDailyTasks(now: now) }
                }
                .buttonStyle(.bordered)
            }
            .padding(FFSpace.s)
            .background(RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous).fill(FFPalette.atRisk.opacity(0.1)))
        }
    }

    /// Type and press Return, or click +. The field is ready when Today opens, and ⌘N jumps to it.
    private var addRow: some View {
        let canAdd = !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: FFSpace.s) {
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(canAdd ? FFPalette.accent : FFPalette.accent.opacity(0.45))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .help(canAdd ? "Add this task (Return)" : "Type a task, then press Return")
            .accessibilityLabel("Add task")
            TextField(todays.isEmpty ? (projectID == nil ? "What would make today a good day?" : "Add a task for \(scopedProject?.name ?? "this project")") : "Add a task", text: $draftTitle)
                .textFieldStyle(.plain)
                .ffText(.body)
                .focused($fieldFocused)
                .onSubmit(add)
                // Today is for planning, so the field is ready; a project page is for reading first.
                .onAppear { if projectID == nil { fieldFocused = true } }
                .background {
                    // ⌘N: jump to the field from anywhere on Today.
                    Button("") { fieldFocused = true }
                        .keyboardShortcut("n", modifiers: .command)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            if projectID == nil { projectMenu }
            resultMenu
        }
        .padding(.horizontal, FFSpace.xs)
        .frame(minHeight: 36)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous))
    }

    private var projectMenu: some View {
        Menu {
            Button("No project") { pickProject(nil) }
            Divider()
            ForEach(projects) { project in
                Button(project.name) { pickProject(project.id) }
            }
        } label: {
            let project = projects.first { $0.id == draftProjectID }
            HStack(spacing: 4) {
                Circle().fill(project.map { FFPalette.project($0.color) } ?? Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(project?.name ?? "Project").lineLimit(1)
            }
            .ffText(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Which project this task is for")
    }

    /// A goal from another project is dropped when the project changes, so the two never disagree.
    private func pickProject(_ id: UUID?) {
        draftProjectID = id
        if let resultID = draftResultID, !keyResults(for: id).contains(where: { $0.result.id == resultID }) {
            draftResultID = nil
        }
    }

    @ViewBuilder
    private var resultMenu: some View {
        let options = keyResults(for: draftProjectID)
        if !options.isEmpty {
            Menu {
                Button("Not linked to a goal") { draftResultID = nil }
                Divider()
                ForEach(options, id: \.result.id) { item in
                    Button("\(item.result.title) · \(item.goal.title)") {
                        draftResultID = item.result.id
                        if draftProjectID == nil { draftProjectID = item.goal.projectID }
                    }
                }
            } label: {
                Label(options.first { $0.result.id == draftResultID }?.result.title ?? "Goal", systemImage: "target")
                    .ffText(.caption)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Link to a goal: finishing this task adds 1 to that result")
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let levers = DailyTaskPlanner.leverSuggestions(GoalDataBuilder.levers(activeGoals, now: now), existing: tasks, on: now)
            .filter { projectID == nil || $0.projectID == projectID }
        if !levers.isEmpty {
            HStack(spacing: FFSpace.s) {
                Text("From your goals").ffText(.caption)
                    .help("What your goals need today to stay on pace. Click one to add it as a task with a counter.")
                ForEach(levers.prefix(3)) { lever in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { _ = timerVM.addLeverTask(lever, now: now) }
                    } label: {
                        Label(lever.action, systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .background(Capsule().fill(lever.status.color.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(lever.status.color.opacity(0.35), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("\(lever.goalTitle) · \(lever.reason)")
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if todays.isEmpty {
            Text(projectID == nil ? "Small beats vague: “2 LeetCode questions”, not “prep”." : "Nothing planned for today yet.")
                .ffText(.caption)
                .padding(.vertical, FFSpace.xs)
        } else {
            VStack(spacing: 2) {
                ForEach(todays) { task in
                    DailyTaskRow(
                        task: task,
                        project: projects.first { $0.id == task.projectID },
                        resultTitle: keyResults.first { $0.result.id == task.keyResultID }?.result.title,
                        onToggle: { withAnimation(.smooth(duration: 0.3)) { timerVM.advanceDailyTask(task, now: Date()) } },
                        onStepDown: { withAnimation(.smooth(duration: 0.3)) { _ = timerVM.stepDailyTask(task, by: -1, now: Date()) } },
                        onMarkDone: { withAnimation(.smooth(duration: 0.3)) { timerVM.setDailyTask(task, done: true, now: Date()) } },
                        onTop: { withAnimation(.smooth(duration: 0.3)) { timerVM.moveDailyTaskToTop(task) } },
                        onTomorrow: { withAnimation(.smooth(duration: 0.3)) { timerVM.moveDailyTaskToTomorrow(task, now: now) } },
                        onDelete: { withAnimation(.smooth(duration: 0.25)) { timerVM.deleteDailyTask(task) } },
                        syncsReminder: remindersOn && task.reminderID != nil
                            && !(projects.first { $0.id == task.projectID }?.reminderListID ?? "").isEmpty,
                        goalOptions: keyResults(for: task.projectID).map { (id: $0.result.id, title: "\($0.result.title) · \($0.goal.title)") },
                        onLink: { resultID in withAnimation(.smooth(duration: 0.25)) { timerVM.linkDailyTask(task, toResult: resultID, now: Date()) } },
                        onRename: { title in timerVM.renameDailyTask(task, to: title) },
                        showsProject: projectID == nil
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func add() {
        guard !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let resultID = draftResultID
        withAnimation(.smooth(duration: 0.25)) {
            _ = timerVM.addDailyTask(title: draftTitle, projectID: draftProjectID, keyResultID: resultID, now: now)
        }
        draftTitle = ""
        draftResultID = nil
        if projectID != nil { draftProjectID = projectID }
        fieldFocused = true
    }
}

/// A small ring and "3 of 5 done".
struct DailyTaskProgressBadge: View {
    let stats: DailyTaskStats

    var body: some View {
        HStack(spacing: FFSpace.s) {
            ZStack {
                Circle().stroke(FFPalette.track, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: stats.fraction)
                    .stroke(FFPalette.goal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if stats.isComplete {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(FFPalette.goal)
                }
            }
            .frame(width: 20, height: 20)
            .animation(.smooth(duration: 0.4), value: stats.fraction)
            Text(stats.label)
                .ffText(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven days of planned against done: a bar per day, filled by the share done.
struct DailyTaskWeekStrip: View {
    let history: [DailyTaskDay]

    var body: some View {
        HStack(alignment: .bottom, spacing: FFSpace.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow-through").ffText(.headline)
                Text(DailyTaskPlanner.weekSummary(history) ?? "Plan a few tasks to see your follow-through.")
                    .ffText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(history) { day in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(FFPalette.track)
                            Capsule()
                                .fill(day.planned > 0 && day.done >= day.planned ? FFPalette.goal : FFPalette.accent)
                                .frame(height: day.planned > 0 ? max(4, 36 * Double(day.done) / Double(day.planned)) : 0)
                        }
                        .frame(width: 10, height: 36)
                        Text(day.planned > 0 ? "\(day.done)/\(day.planned)" : "–")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(day.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Calendar.current.isDateInToday(day.day) ? .primary : .secondary)
                    }
                    .frame(width: 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.day.formatted(.dateTime.weekday(.wide))): \(day.done) of \(day.planned) done")
                }
            }
        }
    }
}
