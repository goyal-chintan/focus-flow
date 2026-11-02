import Foundation

/// Per-project Reminders sync, the pure part (no EventKit, no SwiftData): which reminders become
/// today's tasks and which linked tasks need a look. `TimerViewModel.syncReminders` applies it.
///
/// Rules (Reminders design 2026-10-30; every reminder imported 2026-11-02):
/// - A project may name one Reminders list. Every incomplete reminder in it is one of that
///   project's tasks, once (a task keeps the reminder's ID): due today, overdue or undated on
///   today, due later on its due day. So the whole list is in the project, and any of it can be
///   picked into a goal.
/// - An open linked task (today or later) still in the incomplete fetch follows the reminder's
///   title and its due day (never before today).
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

    /// An open task of today with no reminder (made before sync, or while a write was pending).
    struct UnlinkedTask: Equatable {
        let id: UUID
        let title: String
        let projectID: UUID?
    }

    struct Import: Equatable {
        let reminderID: String
        let title: String
        let projectID: UUID
        /// Today for a reminder due by today, else its due day.
        var day: Date
        /// An earlier unfinished task for the same reminder: the import is its carry-over.
        let carriedFromID: UUID?
    }

    struct Plan: Equatable {
        var imports: [Import] = []
        /// A reminder that matches an unlinked task (same project, same title): linked, not imported.
        var links: [(taskID: UUID, reminderID: String)] = []
        var renames: [(taskID: UUID, title: String)] = []
        /// Rescheduled in Reminders: taskID → its new day (today at the earliest).
        var deferrals: [(taskID: UUID, day: Date)] = []
        /// Unticked in Reminders.
        var reopens: [UUID] = []
        /// Open linked tasks of today or later whose reminder left the incomplete fetch: taskID → reminderID.
        var toCheck: [(taskID: UUID, reminderID: String)] = []

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.imports == rhs.imports
                && lhs.renames.map(\.taskID) == rhs.renames.map(\.taskID) && lhs.renames.map(\.title) == rhs.renames.map(\.title)
                && lhs.toCheck.map(\.taskID) == rhs.toCheck.map(\.taskID) && lhs.toCheck.map(\.reminderID) == rhs.toCheck.map(\.reminderID)
                && lhs.deferrals.map(\.taskID) == rhs.deferrals.map(\.taskID) && lhs.deferrals.map(\.day) == rhs.deferrals.map(\.day)
                && lhs.reopens == rhs.reopens
                && lhs.links.map(\.taskID) == rhs.links.map(\.taskID) && lhs.links.map(\.reminderID) == rhs.links.map(\.reminderID)
        }

        var isEmpty: Bool { imports.isEmpty && links.isEmpty && renames.isEmpty && toCheck.isEmpty && deferrals.isEmpty && reopens.isEmpty }
    }

    /// Due today, overdue, or undated: what a day's task list should hold.
    static func isDueBy(_ due: Date?, endOf day: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return true }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return true }
        return due < tomorrow
    }

    /// The day a reminder's task belongs on: today when due by today or undated, else its due day.
    static func taskDay(for due: Date?, today: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: today)
        guard let due, !isDueBy(due, endOf: today, calendar: calendar) else { return start }
        return calendar.startOfDay(for: due)
    }

    /// - Parameters:
    ///   - open: incomplete reminders in the synced lists.
    ///   - projectForList: list ID → project ID (one list per project).
    ///   - tasks: linked tasks of the carry-over window, today and later.
    static func plan(
        open: [RemindersService.ReminderItem],
        projectForList: [String: UUID],
        tasks: [TaskRef],
        unlinkedToday: [UnlinkedTask] = [],
        today: Date,
        calendar: Calendar = .current
    ) -> Plan {
        var plan = Plan()
        let todayStart = calendar.startOfDay(for: today)
        // Today's and later days' tasks: the ones that mirror the list now.
        let current = tasks.filter { $0.day >= todayStart }
        let linked = Set(current.map(\.reminderID))
        let openByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var unlinked = unlinkedToday
        func normalized(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        for reminder in open {
            guard let projectID = projectForList[reminder.listId], !linked.contains(reminder.id) else { continue }
            let day = taskDay(for: reminder.dueDate, today: today, calendar: calendar)
            let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if day == todayStart,
               let index = unlinked.firstIndex(where: { $0.projectID == projectID && normalized($0.title) == normalized(title) }) {
                plan.links.append((unlinked[index].id, reminder.id))
                unlinked.remove(at: index)
                continue
            }
            let earlier = tasks
                .filter { $0.reminderID == reminder.id && !$0.isDone && $0.day < todayStart }
                .max { $0.day < $1.day }
            plan.imports.append(Import(reminderID: reminder.id, title: title, projectID: projectID, day: day, carriedFromID: earlier?.id))
        }

        for task in current {
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
            let day = taskDay(for: reminder.dueDate, today: today, calendar: calendar)
            if !calendar.isDate(task.day, inSameDayAs: day) {
                plan.deferrals.append((task.id, day))
            }
        }
        return plan
    }
}
