@preconcurrency import EventKit
import Foundation

/// Manages Apple Calendar integration — creates events for completed focus sessions.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private var store: EKEventStore { EventStoreManager.shared.store }
    private var isRequestingAccess = false
    private init() {}

    // MARK: - Authorization

    enum AuthStatus {
        case authorized, denied, notDetermined
    }

    var authStatus: AuthStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
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
            let granted = try await store.requestFullAccessToEvents()
            if granted { try? await Task.sleep(for: .milliseconds(150)) }
            return granted || authStatus == .authorized
        } catch {
            log("Calendar access request failed: \(error)")
            return false
        }
    }

    // MARK: - Calendar Discovery

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

    func calendar(withIdentifier id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    // MARK: - Calendar Selection

    private func resolveCalendar(calendarId: String?, calendarName: String) -> EKCalendar? {
        if let calendarId, let cal = store.calendar(withIdentifier: calendarId) { return cal }
        let calendars = store.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == calendarName }) { return existing }

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

    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        calendarName: String = "FocusFlow",
        calendarId: String? = nil
    ) -> String? {
        guard authStatus == .authorized else { log("Calendar not authorized"); return nil }
        guard let calendar = resolveCalendar(calendarId: calendarId, calendarName: calendarName) else {
            log("Could not resolve calendar"); return nil
        }

        let event = EKEvent(eventStore: store)
        event.title = "🎯 \(title)"
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar

        var noteLines = [String]()
        if let notes, !notes.isEmpty { noteLines.append(notes) }
        noteLines.append("Duration: \(Int(endDate.timeIntervalSince(startDate) / 60)) minutes")
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

    @discardableResult
    func updateEvent(
        eventId: String,
        title: String? = nil,
        notes: String?,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> Bool {
        guard authStatus == .authorized else { return false }
        guard let event = store.event(withIdentifier: eventId) else { return false }
        if let title, !title.isEmpty { event.title = "🎯 \(title)" }
        if let startDate { event.startDate = startDate }
        if let endDate { event.endDate = endDate }
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            log("Failed to update event: \(error)")
            return false
        }
    }

    @discardableResult
    func deleteEvent(eventId: String) -> Bool {
        guard authStatus == .authorized else { return false }
        guard let event = store.event(withIdentifier: eventId) else { return false }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            log("Deleted calendar event: \(eventId)")
            return true
        } catch {
            log("Failed to delete event: \(error)")
            return false
        }
    }

    // MARK: - Availability (coach input)

    private var cachedAvailability: (computedAt: Date, value: CalendarAvailability)?

    /// Busy state and next event start from the user's calendars, for the coach idle path.
    /// Skips all-day, free, cancelled and declined events, and FocusFlow's own session log.
    /// Returns `.unknown` without calendar access. Cached for 60 s because the idle path runs often.
    func availability(
        at now: Date = Date(),
        excludingCalendarId: String? = nil,
        excludingCalendarName: String? = nil
    ) -> CalendarAvailability {
        guard authStatus == .authorized else { return .unknown }
        if let cached = cachedAvailability, abs(now.timeIntervalSince(cached.computedAt)) < 60 {
            return cached.value
        }
        let lookahead = CalendarAvailability.lookaheadSeconds
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-lookahead),
            end: now.addingTimeInterval(lookahead),
            calendars: nil
        )
        let busyIntervals = store.events(matching: predicate).compactMap { event -> DateInterval? in
            guard !event.isAllDay,
                  event.availability != .free,
                  event.status != .canceled,
                  let start = event.startDate,
                  let end = event.endDate,
                  end > start else { return nil }
            if let calendar = event.calendar {
                if let excludingCalendarId, !excludingCalendarId.isEmpty,
                   calendar.calendarIdentifier == excludingCalendarId { return nil }
                if let excludingCalendarName, calendar.title == excludingCalendarName { return nil }
            }
            if event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined {
                return nil
            }
            return DateInterval(start: start, end: end)
        }
        let value = CalendarAvailability.compute(busyIntervals: busyIntervals, now: now)
        cachedAvailability = (now, value)
        return value
    }

    private func log(_ message: String) {
        print("[CalendarService] \(message)")
    }
}

/// Calendar state at one moment, as the coach needs it.
struct CalendarAvailability: Equatable, Sendable {
    /// True when a busy event covers `now`.
    let isBusyNow: Bool
    /// Whole minutes until the next busy event starts, within the lookahead; nil when none.
    let minutesUntilNextEvent: Int?

    static let unknown = CalendarAvailability(isBusyNow: false, minutesUntilNextEvent: nil)
    static let lookaheadSeconds: TimeInterval = 12 * 60 * 60

    static func compute(busyIntervals: [DateInterval], now: Date) -> CalendarAvailability {
        let isBusyNow = busyIntervals.contains { $0.start <= now && now < $0.end }
        let nextStart = busyIntervals
            .map(\.start)
            .filter { $0 > now && $0.timeIntervalSince(now) <= lookaheadSeconds }
            .min()
        let minutes = nextStart.map { Int($0.timeIntervalSince(now) / 60) }
        return CalendarAvailability(isBusyNow: isBusyNow, minutesUntilNextEvent: minutes)
    }
}
