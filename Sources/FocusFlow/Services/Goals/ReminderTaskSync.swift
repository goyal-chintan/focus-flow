import Foundation

/// Per-project Reminders sync, the pure part (no EventKit, no SwiftData): which reminders become
/// today's tasks and which linked tasks need a look. `TimerViewModel.syncReminders` applies it.
///
/// Rules (Reminders design 2026-10-30):
/// - A project may name one Reminders list. Its incomplete reminders due today, overdue, or with
///   no due date become that project's tasks for today, once (a task keeps the reminder's ID).
/// - An open linked task still in the incomplete fetch follows the reminder's title, and moves to
///   the reminder's later due day when it was rescheduled there.
/// - A done linked task whose reminder is incomplete again was unticked in Reminders: reopen it.
/// - An open linked task missing from the fetch was completed, deleted, or moved to a list this
///   project doesn't sync; the caller asks EventKit which (one lookup per such task).
/// - FocusFlow → Reminders (tick, add, move, delete) is written by the view model at change time.
enum ReminderTaskSync {
    /// The parts of a `DailyTask` the plan reads.
    struct TaskRef: Equatable {
        let id: UUID
        let reminderID: String
        let day: Date
        let isDone: Bool
        let title: String
    }

    struct Import: Equatable {
        let reminderID: String
        let title: String
        let projectID: UUID
        /// An earlier unfinished task for the same reminder: the import is its carry-over.
        let carriedFromID: UUID?
    }

    struct Plan: Equatable {
        var imports: [Import] = []
        var renames: [(taskID: UUID, title: String)] = []
        /// Rescheduled to a later day in Reminders: taskID → that day.
        var deferrals: [(taskID: UUID, day: Date)] = []
        /// Unticked in Reminders.
        var reopens: [UUID] = []
        /// Open linked tasks of today whose reminder left the incomplete fetch: taskID → reminderID.
        var toCheck: [(taskID: UUID, reminderID: String)] = []

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.imports == rhs.imports
                && lhs.renames.map(\.taskID) == rhs.renames.map(\.taskID) && lhs.renames.map(\.title) == rhs.renames.map(\.title)
                && lhs.toCheck.map(\.taskID) == rhs.toCheck.map(\.taskID) && lhs.toCheck.map(\.reminderID) == rhs.toCheck.map(\.reminderID)
                && lhs.deferrals.map(\.taskID) == rhs.deferrals.map(\.taskID) && lhs.deferrals.map(\.day) == rhs.deferrals.map(\.day)
                && lhs.reopens == rhs.reopens
        }

        var isEmpty: Bool { imports.isEmpty && renames.isEmpty && toCheck.isEmpty && deferrals.isEmpty && reopens.isEmpty }
    }

    /// Due today, overdue, or undated: what a day's task list should hold.
    static func isDueBy(_ due: Date?, endOf day: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return true }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return true }
        return due < tomorrow
    }

    /// - Parameters:
    ///   - open: incomplete reminders in the synced lists.
    ///   - projectForList: list ID → project ID (one list per project).
    ///   - tasks: recent linked tasks (today and the carry-over window).
    static func plan(
        open: [RemindersService.ReminderItem],
        projectForList: [String: UUID],
        tasks: [TaskRef],
        today: Date,
        calendar: Calendar = .current
    ) -> Plan {
        var plan = Plan()
        let todayTasks = tasks.filter { calendar.isDate($0.day, inSameDayAs: today) }
        let linkedToday = Set(todayTasks.map(\.reminderID))
        let openByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for reminder in open {
            guard let projectID = projectForList[reminder.listId],
                  !linkedToday.contains(reminder.id),
                  isDueBy(reminder.dueDate, endOf: today, calendar: calendar) else { continue }
            let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let earlier = tasks
                .filter { $0.reminderID == reminder.id && !$0.isDone && $0.day < calendar.startOfDay(for: today) }
                .max { $0.day < $1.day }
            plan.imports.append(Import(reminderID: reminder.id, title: title, projectID: projectID, carriedFromID: earlier?.id))
        }

        for task in todayTasks {
            guard let reminder = openByID[task.reminderID] else {
                if !task.isDone { plan.toCheck.append((task.id, task.reminderID)) }
                continue
            }
            if task.isDone {
                plan.reopens.append(task.id)
                continue
            }
            let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, title != task.title { plan.renames.append((task.id, title)) }
            if let due = reminder.dueDate, !isDueBy(due, endOf: today, calendar: calendar) {
                plan.deferrals.append((task.id, calendar.startOfDay(for: due)))
            }
        }
        return plan
    }
}
