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
    }
}
