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

/// One task: tick, title, where it counts, and a menu.
struct DailyTaskRow: View {
    let task: DailyTask
    let project: Project?
    let resultTitle: String?
    let onToggle: () -> Void
    var onTop: (() -> Void)?
    var onTomorrow: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: FFSpace.s) {
            DailyTaskCheck(isDone: task.isDone, action: onToggle)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .ffText(.body)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .lineLimit(2)
                if project != nil || resultTitle != nil || task.carriedFromID != nil {
                    HStack(spacing: FFSpace.s) {
                        if let project {
                            HStack(spacing: 4) {
                                Circle().fill(FFPalette.project(project.color)).frame(width: 6, height: 6)
                                Text(project.name)
                            }
                        }
                        if let resultTitle {
                            Label("+\(Self.amountText(task.progressAmount)) \(resultTitle)", systemImage: "target")
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
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel("Delete task")
            }
        }
        .padding(.horizontal, FFSpace.xs)
        .padding(.vertical, 3)
        .ffHoverRow()
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        .contextMenu {
            Button(task.isDone ? "Mark not done" : "Mark done", action: onToggle)
            if !task.isDone {
                if let onTop { Button("Move to top", action: onTop) }
                if let onTomorrow { Button("Move to tomorrow", action: onTomorrow) }
            }
            if let onDelete {
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(task.isDone ? .isSelected : [])
    }

    static func amountText(_ amount: Double) -> String {
        amount.rounded() == amount ? String(Int(amount)) : String(format: "%.1f", amount)
    }
}

/// Today tab: plan, tick, link to goals, carry over, and the week's planned against done.
struct DailyTasksSection: View {
    let now: Date

    @Environment(TimerViewModel.self) private var timerVM
    @Query private var tasks: [DailyTask]
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]

    @State private var draftTitle = ""
    @State private var draftProjectID: UUID?
    @State private var draftResultID: UUID?
    @FocusState private var fieldFocused: Bool

    init(now: Date) {
        self.now = now
        let since = Calendar.current.date(byAdding: .day, value: -(DailyTaskPlanner.carryOverLookbackDays + 1), to: Calendar.current.startOfDay(for: now)) ?? now
        _tasks = Query(filter: #Predicate<DailyTask> { $0.day >= since })
    }

    private var todays: [DailyTask] { DailyTaskPlanner.tasks(tasks, on: now) }
    private var stats: DailyTaskStats { DailyTaskPlanner.stats(tasks, on: now) }
    private var activeGoals: [ProjectGoal] { goals.filter { $0.status == .active } }
    private var keyResults: [(result: GoalKeyResult, goal: ProjectGoal)] {
        activeGoals.flatMap { goal in goal.sortedKeyResults.map { ($0, goal) } }
    }

    var body: some View {
        let history = DailyTaskPlanner.history(tasks, endingOn: now)
        FFSection("Today's tasks", subtitle: "Tick a task linked to a goal and the goal moves.") {
            if stats.planned > 0 {
                DailyTaskProgressBadge(stats: stats)
            }
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.m) {
                carryOverBanner
                addRow
                suggestions
                list
                // Follow-through needs a little history before it says anything.
                if history.filter({ $0.planned > 0 }).count >= 2 {
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

    private var addRow: some View {
        HStack(spacing: FFSpace.s) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(FFPalette.accent)
                .frame(width: 30)
            TextField(todays.isEmpty ? "What would make today a good day?" : "Add a task", text: $draftTitle)
                .textFieldStyle(.plain)
                .ffText(.body)
                .focused($fieldFocused)
                .onSubmit(add)
            projectMenu
            resultMenu
        }
        .padding(.horizontal, FFSpace.xs)
        .frame(minHeight: 36)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous))
    }

    private var projectMenu: some View {
        Menu {
            Button("No project") { draftProjectID = nil }
            Divider()
            ForEach(projects) { project in
                Button(project.name) { draftProjectID = project.id }
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

    @ViewBuilder
    private var resultMenu: some View {
        if !keyResults.isEmpty {
            Menu {
                Button("Not linked to a goal") { draftResultID = nil }
                Divider()
                ForEach(keyResults, id: \.result.id) { item in
                    Button("\(item.result.title) · \(item.goal.title)") {
                        draftResultID = item.result.id
                        if draftProjectID == nil { draftProjectID = item.goal.projectID }
                    }
                }
            } label: {
                Label(keyResults.first { $0.result.id == draftResultID }?.result.title ?? "Goal", systemImage: "target")
                    .ffText(.caption)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Ticking a linked task adds 1 to this key result")
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let levers = DailyTaskPlanner.leverSuggestions(GoalDataBuilder.levers(activeGoals, now: now), existing: tasks, on: now)
        if !levers.isEmpty {
            HStack(spacing: FFSpace.s) {
                Text("Today's levers").ffText(.caption)
                    .help("From your goals' pace: add one as a task")
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
            Text("Small beats vague: “2 LeetCode questions”, not “prep”.")
                .ffText(.caption)
                .padding(.vertical, FFSpace.xs)
        } else {
            VStack(spacing: 2) {
                ForEach(todays) { task in
                    DailyTaskRow(
                        task: task,
                        project: projects.first { $0.id == task.projectID },
                        resultTitle: keyResults.first { $0.result.id == task.keyResultID }?.result.title,
                        onToggle: { withAnimation(.smooth(duration: 0.3)) { timerVM.setDailyTask(task, done: !task.isDone, now: Date()) } },
                        onTop: { withAnimation(.smooth(duration: 0.3)) { timerVM.moveDailyTaskToTop(task) } },
                        onTomorrow: { withAnimation(.smooth(duration: 0.3)) { timerVM.moveDailyTaskToTomorrow(task, now: now) } },
                        onDelete: { withAnimation(.smooth(duration: 0.25)) { timerVM.deleteDailyTask(task) } }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func add() {
        let resultID = draftResultID
        withAnimation(.smooth(duration: 0.25)) {
            _ = timerVM.addDailyTask(title: draftTitle, projectID: draftProjectID, keyResultID: resultID, now: now)
        }
        draftTitle = ""
        draftResultID = nil
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
