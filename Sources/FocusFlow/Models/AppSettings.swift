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
    var autoResumeOnWake: Bool = true
    var autoResumeThresholdSeconds: Int = 120
    var autoStopOnSleepThresholdMinutes: Int = 60

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

    // Focus Coach v2.1 — learning coach (see Models/CoachV2Models.swift)
    var coachStyleRawValue: String = CoachStyle.challenger.rawValue
    /// On-screen floating panel is the primary prompt surface.
    var coachOnScreenPromptsEnabled: Bool = true
    /// Notifications are opt-in; most users disable them.
    var coachNotificationsEnabled: Bool = false
    var coachMaxPromptsPerDay: Int = 3
    /// Quiet hours as minutes after midnight (local). Default 00:30–07:00.
    var coachQuietStartMinute: Int = 30
    var coachQuietEndMinute: Int = 420
    /// Up to 5 user-written "why" lines, newline-separated.
    var coachMyWhyText: String = ""
    /// Stretch target on top of dailyFocusGoal (personal work), seconds.
    var dailyStretchGoal: TimeInterval = 9000

    // Rescue loop (docs/plans/2026-10-17-coach-rescue-loop-design.md)
    var coachShowDriftInMenuBar: Bool = true
    var coachPauseScreenEnabled: Bool = true
    var coachStarterBlockMinutes: Int = 5
    var coachGlobalHotkeyEnabled: Bool = true

    var coachStyle: CoachStyle {
        get { CoachStyle(rawValue: coachStyleRawValue) ?? .challenger }
        set { coachStyleRawValue = newValue.rawValue }
    }

    var coachMyWhyLines: [String] {
        let lines: [String] = coachMyWhyText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(5))
    }

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
        self.autoResumeOnWake = true
        self.autoResumeThresholdSeconds = 120
        self.autoStopOnSleepThresholdMinutes = 60
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
        self.coachStyleRawValue = CoachStyle.challenger.rawValue
        self.coachOnScreenPromptsEnabled = true
        self.coachNotificationsEnabled = false
        self.coachMaxPromptsPerDay = 3
        self.coachQuietStartMinute = 30
        self.coachQuietEndMinute = 420
        self.coachMyWhyText = ""
        self.dailyStretchGoal = 9000
        self.coachShowDriftInMenuBar = true
        self.coachPauseScreenEnabled = true
        self.coachStarterBlockMinutes = 5
        self.coachGlobalHotkeyEnabled = true
    }
}
