@preconcurrency import EventKit
import Foundation

/// Manages Apple Calendar integration — creates events for completed focus sessions.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private init() {}

    // MARK: - Authorization

    enum AuthStatus {
        case authorized
        case denied
        case notDetermined
    }

    var authStatus: AuthStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized, .writeOnly:
            return .authorized
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            log("Calendar access request failed: \(error)")
            return false
        }
    }

    // MARK: - Calendar Management

    /// Finds or creates the FocusFlow calendar
    private func focusFlowCalendar(named name: String) -> EKCalendar? {
        // Look for existing calendar
        let calendars = store.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == name }) {
            return existing
        }

        // Create new calendar
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = name

        // Use the default calendar source
        if let source = store.defaultCalendarForNewEvents?.source {
            calendar.source = source
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else {
            log("No calendar source available")
            return nil
        }

        // Set a nice color (indigo-ish)
        calendar.cgColor = CGColor(red: 0.24, green: 0.56, blue: 1.0, alpha: 1.0)

        do {
            try store.saveCalendar(calendar, commit: true)
            log("Created FocusFlow calendar: \(name)")
            return calendar
        } catch {
            log("Failed to create calendar: \(error)")
            return nil
        }
    }

    // MARK: - Event Creation

    /// Creates a calendar event for a completed focus session.
    /// Returns the event identifier if successful.
    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        calendarName: String = "FocusFlow"
    ) -> String? {
        guard authStatus == .authorized else {
            log("Calendar not authorized")
            return nil
        }

        guard let calendar = focusFlowCalendar(named: calendarName) else {
            log("Could not get or create calendar")
            return nil
        }

        let event = EKEvent(eventStore: store)
        event.title = "🎯 \(title)"
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar

        // Build notes from session data
        var noteLines = [String]()
        if let notes, !notes.isEmpty {
            noteLines.append(notes)
        }
        let duration = endDate.timeIntervalSince(startDate)
        noteLines.append("Duration: \(Int(duration / 60)) minutes")
        noteLines.append("Recorded by FocusFlow")
        event.notes = noteLines.joined(separator: "\n")

        do {
            try store.save(event, span: .thisEvent, commit: true)
            log("Created calendar event: \(event.eventIdentifier ?? "unknown")")
            return event.eventIdentifier
        } catch {
            log("Failed to save calendar event: \(error)")
            return nil
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        #if DEBUG
        print("[CalendarService] \(message)")
        #endif
    }
}
