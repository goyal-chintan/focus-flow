@preconcurrency import EventKit
import Foundation
import OSLog

/// Manages Apple Reminders integration — read/complete reminders during focus sessions.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    private let store = EKEventStore()
    private let logger = Logger(subsystem: "FocusFlow", category: "RemindersService")
    private init() {}

    // MARK: - Authorization

    enum AuthStatus {
        case authorized
        case denied
        case notDetermined
    }

    var authStatus: AuthStatus {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    // MARK: - Fetch Reminders

    /// Wrapper to make EKReminder arrays Sendable across isolation boundaries.
    private struct ReminderData: Sendable {
        let title: String
        let calendarItemIdentifier: String
        let reminderListIdentifier: String
        let dueDateComponents: DateComponents?
        let isCompleted: Bool
        let listTitle: String
        let notes: String
    }

    struct ReminderItem: Identifiable, Sendable {
        let id: String
        let title: String
        let list: String
        let listId: String
        let dueDate: Date?
        let isCompleted: Bool
        let notes: String
    }

    /// Fetches incomplete reminders from all lists.
    func fetchIncompleteReminderTitles() async -> [(title: String, id: String, list: String)] {
        let items = await fetchIncompleteReminders()
        return items.map { ($0.title, $0.id, $0.list) }
    }

    /// Fetches incomplete reminders from all lists with full details.
    func fetchIncompleteReminders(
        listId: String? = nil,
        dueDateStarting: Date? = nil,
        dueDateEnding: Date? = nil
    ) async -> [ReminderItem] {
        guard authStatus == .authorized else {
            logger.error("fetchIncompleteReminders blocked: reminders not authorized")
            return []
        }

        let calendars: [EKCalendar]?
        if let listId, !listId.isEmpty {
            let matched = store.calendars(for: .reminder).filter { $0.calendarIdentifier == listId }
            if matched.isEmpty {
                logger.error("fetchIncompleteReminders list missing: selectedListId=\(listId, privacy: .public), falling back to all lists")
                calendars = nil
            } else {
                calendars = matched
            }
        } else {
            calendars = nil
        }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: dueDateStarting,
            ending: dueDateEnding,
            calendars: calendars
        )

        let data: [ReminderData] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                let mapped = (result ?? []).map { reminder in
                    ReminderData(
                        title: reminder.title ?? "",
                        calendarItemIdentifier: reminder.calendarItemIdentifier,
                        reminderListIdentifier: reminder.calendar?.calendarIdentifier ?? "",
                        dueDateComponents: reminder.dueDateComponents,
                        isCompleted: reminder.isCompleted,
                        listTitle: reminder.calendar?.title ?? "",
                        notes: reminder.notes ?? ""
                    )
                }
                continuation.resume(returning: mapped)
            }
        }

        let results = data
            .sorted { a, b in
                let aDate = a.dueDateComponents?.date ?? .distantFuture
                let bDate = b.dueDateComponents?.date ?? .distantFuture
                return aDate < bDate
            }
            .map {
                ReminderItem(
                    id: $0.calendarItemIdentifier,
                    title: $0.title,
                    list: $0.listTitle,
                    listId: $0.reminderListIdentifier,
                    dueDate: $0.dueDateComponents?.date,
                    isCompleted: $0.isCompleted,
                    notes: $0.notes
                )
            }
            .reduce(into: [ReminderItem]()) { acc, item in
                if acc.contains(where: { $0.id == item.id }) == false {
                    acc.append(item)
                }
            }
            .sorted {
                let lhs = $0.dueDate ?? .distantFuture
                let rhs = $1.dueDate ?? .distantFuture
                if lhs != rhs { return lhs < rhs }
                if $0.list != $1.list { return $0.list < $1.list }
                return $0.title < $1.title
            }

        logger.debug(
            "fetchIncompleteReminders done: total=\(data.count, privacy: .public) returned=\(results.count, privacy: .public) listFiltered=\(listId != nil, privacy: .public) dateFiltered=\((dueDateStarting != nil || dueDateEnding != nil), privacy: .public)"
        )
        return results
    }

    // MARK: - Complete Reminder

    /// Marks a reminder as completed by its calendarItemIdentifier.
    func completeReminder(identifier: String) -> Bool {
        guard let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return false
        }
        item.isCompleted = true
        item.completionDate = Date()
        do {
            try store.save(item, commit: true)
            return true
        } catch {
            return false
        }
    }

    func updateReminder(identifier: String, title: String, notes: String?, dueDate: Date?) -> Bool {
        guard let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return false
        }
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notes
        if let dueDate {
            item.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        } else {
            item.dueDateComponents = nil
        }
        do {
            try store.save(item, commit: true)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func createReminder(title: String, notes: String?, dueDate: Date?, listId: String?) -> String? {
        guard authStatus == .authorized else { return nil }
        guard let selectedCalendar = resolveReminderCalendar(listId: listId) else { return nil }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = selectedCalendar
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = notes
        reminder.isCompleted = false
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        do {
            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    func reminderLists() -> [(id: String, title: String, source: String)] {
        guard authStatus == .authorized else { return [] }
        return store.calendars(for: .reminder)
            .map { (id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted {
                if $0.source == $1.source {
                    return $0.title < $1.title
                }
                return $0.source < $1.source
            }
    }

    // MARK: - List Names

    var listNames: [String] {
        guard authStatus == .authorized else { return [] }
        return store.calendars(for: .reminder).map(\.title)
    }

    private func resolveReminderCalendar(listId: String?) -> EKCalendar? {
        let calendars = store.calendars(for: .reminder)
        if let listId, !listId.isEmpty,
           let existing = calendars.first(where: { $0.calendarIdentifier == listId }) {
            return existing
        }
        return store.defaultCalendarForNewReminders() ?? calendars.first
    }
}
