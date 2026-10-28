import SwiftUI
import SwiftData

/// Idle popover: today's tasks at a glance (daily tasks design §2). Tick one, or click its title
/// to make it the next block's goal; the block then remembers the task for the end-of-block log.
struct PopoverTasksStrip: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var tasks: [DailyTask]
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]

    private static let shownCount = 3

    init(now: Date = Date()) {
        let since = Calendar.current.startOfDay(for: now)
        _tasks = Query(filter: #Predicate<DailyTask> { $0.day >= since })
    }

    var body: some View {
        let now = Date()
        let stats = DailyTaskPlanner.stats(tasks, on: now)
        let open = DailyTaskPlanner.tasks(tasks, on: now).filter { !$0.isDone }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Today's tasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    timerVM.openCompanionWindow?(.today)
                } label: {
                    HStack(spacing: 3) {
                        Text(stats.planned == 0 ? "Plan today" : stats.label)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(stats.isComplete ? FFPalette.goal : FFPalette.accent)
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Today to plan and edit tasks")
                .accessibilityLabel(stats.planned == 0 ? "Plan today's tasks" : "Today's tasks, \(stats.label)")
            }
            if stats.planned > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FFPalette.track)
                        Capsule()
                            .fill(stats.isComplete ? FFPalette.goal : FFPalette.accent)
                            .frame(width: max(4, proxy.size.width * stats.fraction))
                    }
                }
                .frame(height: 4)
                .padding(.bottom, 2)
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: stats.fraction)
                .accessibilityHidden(true)
            }
            ForEach(open.prefix(Self.shownCount)) { task in
                row(task)
            }
            if open.count > Self.shownCount {
                Text("+\(open.count - Self.shownCount) more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 30)
            }
        }
    }

    private func row(_ task: DailyTask) -> some View {
        let selected = timerVM.pendingTaskID == task.id
        let project = projects.first { $0.id == task.projectID }
        return HStack(spacing: 2) {
            DailyTaskCheck(isDone: task.isDone, size: 15) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    if selected { clear(task) }
                    timerVM.setDailyTask(task, done: true)
                }
            }
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    if selected { clear(task) } else { pick(task, project: project) }
                }
            } label: {
                HStack(spacing: 6) {
                    if let project {
                        Circle().fill(FFPalette.project(project.color)).frame(width: 6, height: 6)
                    }
                    Text(task.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? FFPalette.accent : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(FFPalette.accent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? FFPalette.rowSelected : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(selected ? "This is the next block's goal. Click to clear." : "Make this the next block's goal")
            .accessibilityLabel(selected ? "\(task.title), goal for the next block" : "Make \(task.title) the next block's goal")
        }
    }

    /// Fills the block goal and project from the task.
    private func pick(_ task: DailyTask, project: Project?) {
        timerVM.pendingTaskID = task.id
        timerVM.pendingIntentText = task.title
        if let project { timerVM.selectedProject = project }
    }

    private func clear(_ task: DailyTask) {
        timerVM.pendingTaskID = nil
        if timerVM.pendingIntentText == task.title { timerVM.pendingIntentText = "" }
    }
}
