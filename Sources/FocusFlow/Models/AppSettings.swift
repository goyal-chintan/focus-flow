import Foundation
import SwiftData

@Model
final class AppSettings {
    var focusDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var longBreakDuration: TimeInterval
    var sessionsBeforeLongBreak: Int
    var autoStartBreak: Bool
    var autoStartNextSession: Bool
    var launchAtLogin: Bool
    var completionSound: String

    // Goals
    var dailyFocusGoal: TimeInterval = 7200

    // Integrations
    var calendarIntegrationEnabled: Bool = false
    var calendarName: String = "FocusFlow"
    var selectedCalendarId: String = ""
    var remindersIntegrationEnabled: Bool = false
    var selectedReminderListId: String = ""

    // Focus Coach
    var antiProcrastinationEnabled: Bool = true
    var antiProcrastinationThresholdMinutes: Int = 5

    // Focus Coach v2 — Realtime coaching
    var coachRealtimeEnabled: Bool = true
    var coachPromptBudgetPerSession: Int = 4
    var coachReasonPromptsEnabled: Bool = true
    var coachDefaultSnoozeMinutes: Int = 10
    var coachCollectRawDomains: Bool = false
    var coachIdleStarterEnabled: Bool = true
    var coachAutoOpenPopoverOnStrongPrompt: Bool = true
    var coachBringAppToFrontOnStrongPrompt: Bool = true
    var coachSuppressPopupsDuringScreenShare: Bool = true
    var coachAllowSkipAction: Bool = true
    var coachMaxStrongPromptsPerSession: Int = 2
    var coachInterventionModeRawValue: String = FocusCoachInterventionMode.balanced.rawValue
    var coachPassivePromptSeconds: Int = 120
    var coachPassiveEscalationSeconds: Int = 240
    var coachAdaptivePromptSeconds: Int = 90
    var coachAdaptiveEscalationSeconds: Int = 180
    var coachStrictPromptSeconds: Int = 60
    var coachStrictEscalationSeconds: Int = 120

    var coachInterventionMode: FocusCoachInterventionMode {
        get { FocusCoachInterventionMode(rawValue: coachInterventionModeRawValue) ?? .balanced }
        set { coachInterventionModeRawValue = newValue.rawValue }
    }

    // Smart defaults
    var lastUsedProjectId: String? = nil

    init() {
        self.focusDuration = 25 * 60
        self.shortBreakDuration = 5 * 60
        self.longBreakDuration = 15 * 60
        self.sessionsBeforeLongBreak = 4
        self.autoStartBreak = true
        self.autoStartNextSession = false
        self.launchAtLogin = false
        self.completionSound = "Glass"
        self.dailyFocusGoal = 7200  // 120 min
        self.calendarIntegrationEnabled = false
        self.calendarName = "FocusFlow"
        self.selectedCalendarId = ""
        self.remindersIntegrationEnabled = false
        self.selectedReminderListId = ""
        self.antiProcrastinationEnabled = true
        self.antiProcrastinationThresholdMinutes = 5
        self.coachRealtimeEnabled = true
        self.coachPromptBudgetPerSession = 4
        self.coachReasonPromptsEnabled = true
        self.coachDefaultSnoozeMinutes = 10
        self.coachCollectRawDomains = false
        self.coachIdleStarterEnabled = true
        self.coachAutoOpenPopoverOnStrongPrompt = true
        self.coachBringAppToFrontOnStrongPrompt = true
        self.coachSuppressPopupsDuringScreenShare = true
        self.coachAllowSkipAction = true
        self.coachMaxStrongPromptsPerSession = 2
        self.coachInterventionModeRawValue = FocusCoachInterventionMode.balanced.rawValue
        self.coachPassivePromptSeconds = 120
        self.coachPassiveEscalationSeconds = 240
        self.coachAdaptivePromptSeconds = 90
        self.coachAdaptiveEscalationSeconds = 180
        self.coachStrictPromptSeconds = 60
        self.coachStrictEscalationSeconds = 120
    }
}
