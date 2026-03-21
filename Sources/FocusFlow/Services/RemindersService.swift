@preconcurrency import EventKit
import Foundation
import OSLog

/// Manages Apple Reminders integration — read/complete reminders during focus sessions.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    private var store: EKEventStore { EventStoreManager.shared.store }
    private var isRequestingAccess = false
    private let logger = Logger(subsystem: "FocusFlow", category: "RemindersService")
    private init() {}

    // MARK: - Authorization

    enum AuthStatus {
        case authorized, denied, notDetermined
    }

    var authStatus: AuthStatus {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized, .writeOnly: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        if authStatus == .authorized { return true }
        if authStatus == .denied { return false }
        guard !isRequestingAccess else { return false }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        do {
            let granted = try await store.requestFullAccessToReminders()
            if granted { try? await Task.sleep(for: .milliseconds(150)) }
            return granted || authStatus == .authorized
        } catch {
            logger.error("requestAccess failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - Sendable Data Transfer

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

    // MARK: - Fetch

    func fetchIncompleteReminderTitles() async -> [(title: String, id: String, list: String)] {
        let items = await fetchIncompleteReminders()
        return items.map { ($0.title, $0.id, $0.list) }
    }

    /// Fetches incomplete reminders. All EKReminder property access is dispatched
    /// to the main thread because EventKit's callback runs on an arbitrary queue
    /// and EKReminder properties have internal main-thread assertions.
    func fetchIncompleteReminders(
        listId: String? = nil,
        dueDateStarting: Date? = nil,
        dueDateEnding: Date? = nil
    ) async -> [ReminderItem] {
        guard authStatus == .authorized else { return [] }

        let calendars: [EKCalendar]?
        if let listId, !listId.isEmpty {
            let matched = store.calendars(for: .reminder).filter { $0.calendarIdentifier == listId }
            calendars = matched.isEmpty ? nil : matched
        } else {
            calendars = nil
        }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: dueDateStarting,
            ending: dueDateEnding,
            calendars: calendars
        )

        // CRITICAL: store.fetchReminders calls its completion on an arbitrary background queue.
        // EKReminder properties (.calendar, .dueDateComponents, .title, etc.) are backed by
        // EventKit/CoreData internals that assert main-thread access. We MUST dispatch back
        // to the main queue before reading ANY property on the returned EKReminder objects.
        let data: [ReminderData] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                DispatchQueue.main.async {
                    let mapped = (reminders ?? []).map { reminder in
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

        // EventKit returns dueDateComponents without .calendar set — calling .date
        // returns a sentinel year-4001 value. Use Calendar.current.date(from:) instead.
        let results = data
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
                if !acc.contains(where: { $0.id == item.id }) { acc.append(item) }
            }
            .sorted {
                let lhs = $0.dueDate ?? .distantFuture
                let rhs = $1.dueDate ?? .distantFuture
                if lhs != rhs { return lhs < rhs }
                if $0.list != $1.list { return $0.list < $1.list }
                return $0.title < $1.title
            }

        logger.debug("fetchIncompleteReminders: \(results.count, privacy: .public) items")
        return results
    }

    // MARK: - CRUD

    func completeReminder(identifier: String) -> Bool {
        guard let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        item.isCompleted = true
        item.completionDate = Date()
        do { try store.save(item, commit: true); return true }
        catch { return false }
    }

    func updateReminder(identifier: String, title: String, notes: String?, dueDate: Date?) -> Bool {
        guard let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notes
        if let dueDate {
            item.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            item.dueDateComponents = nil
        }
        do { try store.save(item, commit: true); return true }
        catch { return false }
    }

    @discardableResult
    func createReminder(title: String, notes: String?, dueDate: Date?, listId: String?) -> String? {
        guard authStatus == .authorized else { return nil }
        guard let cal = resolveReminderCalendar(listId: listId) else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = cal
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = notes
        reminder.isCompleted = false
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        do { try store.save(reminder, commit: true); return reminder.calendarItemIdentifier }
        catch { return nil }
    }

    func reminderLists() -> [(id: String, title: String, source: String)] {
        guard authStatus == .authorized else { return [] }
        return store.calendars(for: .reminder)
            .map { (id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted {
                if $0.source == $1.source { return $0.title < $1.title }
                return $0.source < $1.source
            }
    }

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
