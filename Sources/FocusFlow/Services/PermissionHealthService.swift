import AppKit
import CoreGraphics
import CoreServices
import Foundation

enum PermissionHealthStatus: Equatable {
    case ready
    case needsAction
    case notRequested
    case unavailable

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .needsAction:
            return "Needs action"
        case .notRequested:
            return "Not requested"
        case .unavailable:
            return "Unavailable"
        }
    }
}

enum PermissionHealthAction: Equatable {
    case requestNotifications
    case openNotificationSettings
    case requestCalendarPermission
    case openCalendarSettings
    case requestRemindersPermission
    case openRemindersSettings
    case openIntegrationsSection
    case openAutomationSettings
    case openScreenRecordingSettings
}

struct BrowserAutomationTargetStatus: Equatable {
    let target: BrowserAutomationTarget
    let status: PermissionHealthStatus
}

struct PermissionHealthRow: Identifiable, Equatable {
    enum Kind: String {
        case notifications
        case calendar
        case reminders
        case automation
        case screenRecording
    }

    let kind: Kind
    let icon: String
    let title: String
    let message: String
    let status: PermissionHealthStatus
    let actionTitle: String
    let action: PermissionHealthAction
    let detailLines: [String]

    var id: Kind { kind }
}

@MainActor
struct PermissionHealthService {
    var notificationStateProvider: () -> NotificationService.AuthorizationState = {
        NotificationService.shared.authorizationState
    }
    var calendarStatusProvider: () -> CalendarService.AuthStatus = {
        CalendarService.shared.authStatus
    }
    var remindersStatusProvider: () -> RemindersService.AuthStatus = {
        RemindersService.shared.authStatus
    }
    var screenRecordingAccessProvider: () -> Bool = {
        CGPreflightScreenCaptureAccess()
    }
    var installedAutomationTargetsProvider: () -> [BrowserAutomationTarget] = {
        BrowserDomainResolver.supportedAutomationTargets.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
        }
    }
    var automationStatusProvider: (BrowserAutomationTarget) -> PermissionHealthStatus = {
        BrowserAutomationPermissionProbe.status(for: $0)
    }

    func rows(
        calendarIntegrationEnabled: Bool,
        remindersIntegrationEnabled: Bool
    ) -> [PermissionHealthRow] {
        [
            notificationRow(),
            calendarRow(integrationEnabled: calendarIntegrationEnabled),
            remindersRow(integrationEnabled: remindersIntegrationEnabled),
            automationRow(),
            screenRecordingRow()
        ]
    }

    static func automationStatus(for bundleIdentifier: String?) -> PermissionHealthStatus? {
        guard let normalizedBundleIdentifier = bundleIdentifier?.lowercased(),
              let target = BrowserDomainResolver.supportedAutomationTargets.first(where: {
                  $0.bundleIdentifier == normalizedBundleIdentifier
              }) else {
            return nil
        }
        return BrowserAutomationPermissionProbe.status(for: target)
    }

    private func notificationRow() -> PermissionHealthRow {
        switch notificationStateProvider() {
        case .authorized:
            return PermissionHealthRow(
                kind: .notifications,
                icon: "bell.badge.fill",
                title: "Notifications",
                message: "Alerts are available for session completions, break boundaries, and coach nudges.",
                status: .ready,
                actionTitle: "Open Notification Settings",
                action: .openNotificationSettings,
                detailLines: []
            )
        case .notDetermined:
            return PermissionHealthRow(
                kind: .notifications,
                icon: "bell.badge.fill",
                title: "Notifications",
                message: "FocusFlow has not asked for notification permission yet.",
                status: .notRequested,
                actionTitle: "Enable Notifications",
                action: .requestNotifications,
                detailLines: []
            )
        case .denied:
            return PermissionHealthRow(
                kind: .notifications,
                icon: "bell.badge.fill",
                title: "Notifications",
                message: "FocusFlow cannot alert you from the desktop until notification access is restored.",
                status: .needsAction,
                actionTitle: "Open Notification Settings",
                action: .openNotificationSettings,
                detailLines: []
            )
        }
    }

    private func calendarRow(integrationEnabled: Bool) -> PermissionHealthRow {
        switch calendarStatusProvider() {
        case .authorized:
            return PermissionHealthRow(
                kind: .calendar,
                icon: "calendar.badge.clock",
                title: "Calendar",
                message: integrationEnabled
                    ? "Calendar access is granted and FocusFlow can write sessions into your selected calendar."
                    : "Calendar access is granted. Turn on Record to Calendar in Integrations when you want session logging.",
                status: .ready,
                actionTitle: "Open Calendar Setup",
                action: .openIntegrationsSection,
                detailLines: []
            )
        case .notDetermined:
            return PermissionHealthRow(
                kind: .calendar,
                icon: "calendar.badge.clock",
                title: "Calendar",
                message: "FocusFlow has not asked for Calendar access yet.",
                status: .notRequested,
                actionTitle: "Enable Calendar Access",
                action: .requestCalendarPermission,
                detailLines: []
            )
        case .denied:
            return PermissionHealthRow(
                kind: .calendar,
                icon: "calendar.badge.clock",
                title: "Calendar",
                message: "Calendar logging is blocked until you re-enable Calendar access in System Settings.",
                status: .needsAction,
                actionTitle: "Open Calendar Settings",
                action: .openCalendarSettings,
                detailLines: []
            )
        }
    }

    private func remindersRow(integrationEnabled: Bool) -> PermissionHealthRow {
        switch remindersStatusProvider() {
        case .authorized:
            return PermissionHealthRow(
                kind: .reminders,
                icon: "checklist",
                title: "Reminders",
                message: integrationEnabled
                    ? "Reminders access is granted and FocusFlow can read from your selected reminder list."
                    : "Reminders access is granted. Turn on Sync Reminders in Integrations when you want task context inside FocusFlow.",
                status: .ready,
                actionTitle: "Open Reminders Setup",
                action: .openIntegrationsSection,
                detailLines: []
            )
        case .notDetermined:
            return PermissionHealthRow(
                kind: .reminders,
                icon: "checklist",
                title: "Reminders",
                message: "FocusFlow has not asked for Reminders access yet.",
                status: .notRequested,
                actionTitle: "Enable Reminders Access",
                action: .requestRemindersPermission,
                detailLines: []
            )
        case .denied:
            return PermissionHealthRow(
                kind: .reminders,
                icon: "checklist",
                title: "Reminders",
                message: "Reminder sync is blocked until you re-enable Reminders access in System Settings.",
                status: .needsAction,
                actionTitle: "Open Reminders Settings",
                action: .openRemindersSettings,
                detailLines: []
            )
        }
    }

    private func automationRow() -> PermissionHealthRow {
        let targets = installedAutomationTargetsProvider()
        guard !targets.isEmpty else {
            return PermissionHealthRow(
                kind: .automation,
                icon: "hand.raised.app",
                title: "Browser Automation",
                message: "No supported browsers are currently installed, so website-level browser recovery is unavailable.",
                status: .unavailable,
                actionTitle: "Open Automation Settings",
                action: .openAutomationSettings,
                detailLines: []
            )
        }

        let statuses = targets.map { BrowserAutomationTargetStatus(target: $0, status: automationStatusProvider($0)) }
        let detailLines = statuses.map { "\($0.target.displayName): \($0.status.title)" }
        let aggregateStatus = aggregateAutomationStatus(for: statuses)
        let message: String

        switch aggregateStatus {
        case .ready:
            message = "Browser Automation is approved for your installed supported browsers, so FocusFlow can ask them for active tab URLs."
        case .notRequested:
            message = "FocusFlow has not been approved to automate your supported browsers yet."
        case .needsAction:
            message = "At least one installed browser still needs Automation approval before FocusFlow can read its active tab URL."
        case .unavailable:
            message = "No supported browsers are currently installed, so website-level browser recovery is unavailable."
        }

        return PermissionHealthRow(
            kind: .automation,
            icon: "hand.raised.app",
            title: "Browser Automation",
            message: message,
            status: aggregateStatus,
            actionTitle: "Open Automation Settings",
            action: .openAutomationSettings,
            detailLines: detailLines
        )
    }

    private func screenRecordingRow() -> PermissionHealthRow {
        let isEnabled = screenRecordingAccessProvider()
        return PermissionHealthRow(
            kind: .screenRecording,
            icon: "record.circle",
            title: "Screen Recording",
            message: isEnabled
                ? "Screen Recording fallback is ready when a browser only exposes its window title."
                : "Screen Recording fallback is off, so FocusFlow cannot recover browser titles when URL access is unavailable.",
            status: isEnabled ? .ready : .needsAction,
            actionTitle: "Open Screen Recording Settings",
            action: .openScreenRecordingSettings,
            detailLines: []
        )
    }

    private func aggregateAutomationStatus(for statuses: [BrowserAutomationTargetStatus]) -> PermissionHealthStatus {
        guard !statuses.isEmpty else { return .unavailable }
        if statuses.allSatisfy({ $0.status == .ready }) {
            return .ready
        }
        if statuses.contains(where: { $0.status == .needsAction }) {
            return .needsAction
        }
        if statuses.allSatisfy({ $0.status == .notRequested }) {
            return .notRequested
        }
        return .needsAction
    }
}

enum BrowserAutomationPermissionProbe {
    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func status(for target: BrowserAutomationTarget) -> PermissionHealthStatus {
        // AppleEvent automation permission checks can block indefinitely under xctest,
        // which stalls non-interactive screenshot and unit-test runs.
        guard !isRunningUnderXCTest else {
            return .notRequested
        }

        let descriptor = NSAppleEventDescriptor(bundleIdentifier: target.bundleIdentifier)
        let result = AEDeterminePermissionToAutomateTarget(
            descriptor.aeDesc,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEGetData),
            false
        )

        switch result {
        case noErr:
            return .ready
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notRequested
        case OSStatus(errAEEventNotPermitted):
            return .needsAction
        default:
            return .needsAction
        }
    }
}
