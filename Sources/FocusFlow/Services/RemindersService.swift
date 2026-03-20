@preconcurrency import EventKit
import Foundation

/// Manages Apple Reminders integration — read/complete reminders during focus sessions.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    private let store = EKEventStore()
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

    nonisolated func requestAccess() async -> Bool {
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
        let dueDateComponents: DateComponents?
        let isCompleted: Bool
        let listTitle: String
    }

    /// Fetches incomplete reminders from all lists.
    func fetchIncompleteReminderTitles() async -> [(title: String, id: String, list: String)] {
        guard authStatus == .authorized else { return [] }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        let data: [ReminderData] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                let mapped = (result ?? []).map { reminder in
                    ReminderData(
                        title: reminder.title ?? "",
                        calendarItemIdentifier: reminder.calendarItemIdentifier,
                        dueDateComponents: reminder.dueDateComponents,
                        isCompleted: reminder.isCompleted,
                        listTitle: reminder.calendar?.title ?? ""
                    )
                }
                continuation.resume(returning: mapped)
            }
        }

        return data
            .sorted { a, b in
                let aDate = a.dueDateComponents?.date ?? .distantFuture
                let bDate = b.dueDateComponents?.date ?? .distantFuture
                return aDate < bDate
            }
            .map { (title: $0.title, id: $0.calendarItemIdentifier, list: $0.listTitle) }
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

    // MARK: - List Names

    var listNames: [String] {
        guard authStatus == .authorized else { return [] }
        return store.calendars(for: .reminder).map(\.title)
    }
}
