@preconcurrency import EventKit
import Foundation
import OSLog

/// Manages Apple Reminders integration — read/complete reminders during focus sessions.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    /// Shared EKEventStore — never create a second one per Apple's docs.
    private var store: EKEventStore { EventStoreManager.shared.store }
    /// Prevents concurrent requestFullAccessToReminders() calls on the same store.
    private var isRequestingAccess = false
    /// Prevents concurrent EKEventStore.fetchReminders() calls on the same store.
    /// EventKit dispatches its completion callback to the calling queue; two concurrent
    /// fetchReminders calls produce a libdispatch queue-assertion crash.
    private var isFetchingReminders = false
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
        case .writeOnly:
            return .authorized
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        switch authStatus {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            break
        }
        // Guard against concurrent permission requests — EventKit behaviour is undefined
        // if requestFullAccessToReminders() is called while another request is in flight.
        guard !isRequestingAccess else {
            while isRequestingAccess {
                if Task.isCancelled { return false }
                try? await Task.sleep(for: .milliseconds(25))
            }
            return authStatus == .authorized
        }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        return await EventStoreManager.shared.withExclusiveAccess(operation: "reminders.requestAccess") {
            do {
                let granted = try await store.requestFullAccessToReminders()
                // Brief yield so EventKit can finish updating its internal state after grant.
                if granted { try? await Task.sleep(for: .milliseconds(100)) }
                let effectiveGranted = granted || authStatus == .authorized
                logger.debug("requestFullAccessToReminders granted=\(granted, privacy: .public) effectiveGranted=\(effectiveGranted, privacy: .public)")
                return effectiveGranted
            } catch {
                logger.error("requestFullAccessToReminders failed: \(String(describing: error), privacy: .public)")
                return false
            }
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
        // Serialize: EventKit dispatches its callback back to the calling queue (main thread).
        // Two concurrent fetchReminders calls on the same store produce a libdispatch
        // "Block was expected to execute on queue [main-thread]" assertion crash.
        while isFetchingReminders {
            if Task.isCancelled { return [] }
            logger.debug("fetchIncompleteReminders: waiting for in-flight fetch")
            try? await Task.sleep(for: .milliseconds(25))
        }
        isFetchingReminders = true
        defer { isFetchingReminders = false }

        let data: [ReminderData] = await EventStoreManager.shared.withExclusiveAccess(operation: "reminders.fetch") {
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

            // EventKit's fetchReminders always calls its completion handler (with nil on failure),
            // so withCheckedContinuation won't hang. The nil case returns [] via the ?? guard.
            return await withCheckedContinuation { continuation in
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
        }

        // EventKit returns dueDateComponents without .calendar set — calling .date on such a
        // DateComponents returns a sentinel year-4001 value instead of the actual date.
        // Always resolve via Calendar.current.date(from:) to get the correct date.
        let results = data
            .sorted { a, b in
                let aDate = a.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture
                let bDate = b.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture
                return aDate < bDate
            }
            .map {
                ReminderItem(
                    id: $0.calendarItemIdentifier,
                    title: $0.title,
                    list: $0.listTitle,
                    listId: $0.reminderListIdentifier,
                    dueDate: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
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
    func completeReminder(identifier: String) async -> Bool {
        await EventStoreManager.shared.withExclusiveAccess(operation: "reminders.complete") {
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
    }

    func updateReminder(identifier: String, title: String, notes: String?, dueDate: Date?) async -> Bool {
        await EventStoreManager.shared.withExclusiveAccess(operation: "reminders.update") {
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
    }

    @discardableResult
    func createReminder(title: String, notes: String?, dueDate: Date?, listId: String?) async -> String? {
        await EventStoreManager.shared.withExclusiveAccess(operation: "reminders.create") {
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
    }

    func reminderLists() async -> [(id: String, title: String, source: String)] {
        await EventStoreManager.shared.withExclusiveAccess(operation: "reminders.listCalendars") {
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
