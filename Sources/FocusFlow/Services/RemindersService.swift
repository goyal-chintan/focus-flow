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
        let listTitle: String
    }

    /// What the task sync reads from a reminder.
    struct ReminderItem: Identifiable, Sendable, Equatable, Hashable {
        let id: String
        let title: String
        let list: String
        let listId: String
        let dueDate: Date?
    }

    // MARK: - Fetch

    /// Incomplete reminders in `listIds` (nil = every list). Lists that no longer exist are
    /// skipped; when none is left the result is empty. EventKit fetches off the main thread; every
    /// EKReminder property is then read on the main thread (EventKit asserts it).
    func fetchIncompleteReminders(
        in listIds: [String]?,
        dueDateStarting: Date? = nil,
        dueDateEnding: Date? = nil
    ) async -> [ReminderItem] {
        guard authStatus == .authorized else { return [] }

        let calendars: [EKCalendar]?
        if let listIds {
            // Lists that no longer exist return nothing, never every list (nil means "all").
            let wanted = Set(listIds)
            let matched = store.calendars(for: .reminder).filter { wanted.contains($0.calendarIdentifier) }
            guard !matched.isEmpty else { return [] }
            calendars = matched
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
                            listTitle: reminder.calendar?.title ?? ""
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
                    dueDate: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
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

    /// Ticks or unticks a reminder. Does nothing (and returns true) when it already matches.
    @discardableResult
    func setReminderCompleted(identifier: String, _ completed: Bool) -> Bool {
        guard authStatus == .authorized,
              let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        guard item.isCompleted != completed else { return true }
        item.isCompleted = completed
        item.completionDate = completed ? Date() : nil
        do { try store.save(item, commit: true); return true }
        catch { logger.error("setReminderCompleted failed: \(error.localizedDescription, privacy: .public)"); return false }
    }

    enum ReminderState: Equatable {
        case open(title: String)
        case completed
        /// Deleted, or no longer readable.
        case missing
    }

    /// One reminder's state, for a linked task whose reminder left the incomplete fetch.
    func reminderState(identifier: String) -> ReminderState {
        guard authStatus == .authorized,
              let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return .missing }
        return item.isCompleted ? .completed : .open(title: item.title ?? "")
    }

    /// Renames a reminder (its task was renamed in FocusFlow).
    @discardableResult
    func setReminderTitle(identifier: String, _ title: String) -> Bool {
        guard authStatus == .authorized,
              let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        item.title = title
        do { try store.save(item, commit: true); return true }
        catch { logger.error("setReminderTitle failed: \(error.localizedDescription, privacy: .public)"); return false }
    }

    /// Sets a reminder's due day (date only, no time), e.g. when its task moves to tomorrow.
    @discardableResult
    func setReminderDueDay(identifier: String, _ day: Date?) -> Bool {
        guard authStatus == .authorized,
              let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        item.dueDateComponents = day.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
        do { try store.save(item, commit: true); return true }
        catch { logger.error("setReminderDueDay failed: \(error.localizedDescription, privacy: .public)"); return false }
    }

    /// Creates a reminder in exactly `listId`, due on `day` (date only). Nil when the list is gone,
    /// so a task never lands in some other list.
    func createReminder(title: String, dueDay: Date?, listId: String) -> String? {
        guard authStatus == .authorized,
              let cal = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == listId }) else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = cal
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.dueDateComponents = dueDay.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
        do { try store.save(reminder, commit: true); return reminder.calendarItemIdentifier }
        catch { logger.error("createReminder failed: \(error.localizedDescription, privacy: .public)"); return nil }
    }

    /// Creates a Reminders list named `title` in the same account as the default list.
    func createList(title: String) -> String? {
        guard authStatus == .authorized,
              let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else { return nil }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = title
        list.source = source
        do { try store.saveCalendar(list, commit: true); return list.calendarIdentifier }
        catch { logger.error("createList failed: \(error.localizedDescription, privacy: .public)"); return nil }
    }

    /// Deletes a reminder (only after the user confirms "Delete from both" on its task).
    @discardableResult
    func deleteReminder(identifier: String) -> Bool {
        guard authStatus == .authorized,
              let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        do { try store.remove(item, commit: true); return true }
        catch { logger.error("deleteReminder failed: \(error.localizedDescription, privacy: .public)"); return false }
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
}

/// What the task sync needs from Reminders; `RemindersService` in the app, a fake in tests.
@MainActor
protocol ReminderBridge: AnyObject {
    /// Permission granted (the Settings toggle is checked separately).
    var isAuthorized: Bool { get }
    func fetchIncompleteReminders(in listIds: [String]?, dueDateStarting: Date?, dueDateEnding: Date?) async -> [RemindersService.ReminderItem]
    func reminderState(identifier: String) -> RemindersService.ReminderState
    @discardableResult func setReminderCompleted(identifier: String, _ completed: Bool) -> Bool
    @discardableResult func setReminderDueDay(identifier: String, _ day: Date?) -> Bool
    @discardableResult func setReminderTitle(identifier: String, _ title: String) -> Bool
    func createReminder(title: String, dueDay: Date?, listId: String) -> String?
    @discardableResult func deleteReminder(identifier: String) -> Bool
}

extension RemindersService: ReminderBridge {
    var isAuthorized: Bool { authStatus == .authorized }
}
