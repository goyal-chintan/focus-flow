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

    // MARK: - Calendar Discovery

    /// Returns all available calendars grouped by source (iCloud, Gmail, Local, etc.)
    func availableCalendars() -> [(source: String, calendars: [(id: String, title: String)])] {
        guard authStatus == .authorized else { return [] }
        let allCalendars = store.calendars(for: .event)
        var grouped = [String: [(id: String, title: String)]]()
        for cal in allCalendars {
            let sourceName = cal.source?.title ?? "Local"
            grouped[sourceName, default: []].append((id: cal.calendarIdentifier, title: cal.title))
        }
        return grouped.map { (source: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    /// Finds a calendar by its identifier
    func calendar(withIdentifier id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    // MARK: - Calendar Selection

    /// Resolves the target calendar — uses the selected calendar ID if set, otherwise creates a FocusFlow calendar
    private func resolveCalendar(calendarId: String?, calendarName: String) -> EKCalendar? {
        // Try user-selected calendar first
        if let calendarId, let cal = store.calendar(withIdentifier: calendarId) {
            return cal
        }

        // Fall back to finding/creating a calendar by name
        let calendars = store.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == calendarName }) {
            return existing
        }

        // Create new calendar as last resort
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarName

        if let source = store.defaultCalendarForNewEvents?.source {
            calendar.source = source
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else {
            log("No calendar source available")
            return nil
        }

        calendar.cgColor = CGColor(red: 0.24, green: 0.56, blue: 1.0, alpha: 1.0)

        do {
            try store.saveCalendar(calendar, commit: true)
            log("Created FocusFlow calendar: \(calendarName)")
            return calendar
        } catch {
            log("Failed to create calendar: \(error)")
            return nil
        }
    }

    // MARK: - Event Creation

    /// Creates a calendar event for a completed focus session.
    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        calendarName: String = "FocusFlow",
        calendarId: String? = nil
    ) -> String? {
        guard authStatus == .authorized else {
            log("Calendar not authorized")
            return nil
        }

        guard let calendar = resolveCalendar(calendarId: calendarId, calendarName: calendarName) else {
            log("Could not resolve calendar")
            return nil
        }

        let event = EKEvent(eventStore: store)
        event.title = "🎯 \(title)"
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar

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
