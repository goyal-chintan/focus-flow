import EventKit
import OSLog

/// Single shared EKEventStore for the entire app.
/// Apple's documentation explicitly requires ONE store per app — creating
/// multiple stores is expensive and can cause crashes when permissions change.
///
/// Also provides permission reconciliation: on every app activation the manager
/// checks whether the actual TCC grant still matches the persisted integration
/// flags in AppSettings. If macOS revoked access (e.g. after a code-signing
/// change, an OS update, or a manual toggle in System Settings) the flags are
/// automatically disabled so the user sees an accurate UI instead of silent
/// failures.
@MainActor
final class EventStoreManager {
    static let shared = EventStoreManager()
    let store = EKEventStore()
    private let logger = Logger(subsystem: "FocusFlow", category: "EventStoreManager")

    /// Posted when reconciliation auto-disables an integration because the
    /// underlying TCC permission was revoked.
    static let permissionsDidChange = Notification.Name("FocusFlow.permissionsDidChange")

    private init() {}

    // MARK: - Permission Reconciliation

    /// Compares actual TCC authorization against the stored integration flags.
    /// If a permission has been revoked since the flag was last set, the flag
    /// is cleared and a notification is posted so the UI can react.
    ///
    /// Safe to call frequently — it's a cheap in-process check, not a system
    /// dialog trigger.
    func reconcilePermissions(settings: AppSettings) {
        var changed = false

        if settings.calendarIntegrationEnabled {
            let status = EKEventStore.authorizationStatus(for: .event)
            let authorized = status == .fullAccess || status == .authorized || status == .writeOnly
            if !authorized {
                logger.warning("Calendar permission revoked — disabling integration flag")
                settings.calendarIntegrationEnabled = false
                settings.selectedCalendarId = ""
                changed = true
            }
        }

        if settings.remindersIntegrationEnabled {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            let authorized = status == .fullAccess || status == .authorized || status == .writeOnly
            if !authorized {
                logger.warning("Reminders permission revoked — disabling integration flag")
                settings.remindersIntegrationEnabled = false
                settings.selectedReminderListId = ""
                changed = true
            }
        }

        if changed {
            NotificationCenter.default.post(name: Self.permissionsDidChange, object: nil)
        }
    }
}
