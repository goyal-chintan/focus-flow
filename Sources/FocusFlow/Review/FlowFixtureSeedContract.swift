import Foundation

struct FlowFixtureDefinition: Hashable {
    let id: String
    let requiredBeforeStateKeys: [String]
    let requiredAfterStateKeys: [String]
}

enum FlowFixtureSeedContract {
    static let requiredSeedKeys: [String] = [
        "projects",
        "sessions",
        "reminders",
        "appUsageEntries",
        "coachRiskLevels"
    ]

    static let canonicalFlows: [FlowFixtureDefinition] = [
        FlowFixtureDefinition(
            id: "focus_start_pause_resume_stop",
            requiredBeforeStateKeys: ["state", "remainingSeconds", "currentSessionID"],
            requiredAfterStateKeys: ["state", "completedSessionCount", "lastCompletedSessionID"]
        ),
        FlowFixtureDefinition(
            id: "completion_take_break_continue_end",
            requiredBeforeStateKeys: ["state", "isOvertime", "lastCompletedSessionID"],
            requiredAfterStateKeys: ["state", "todayFocusTime", "lastCompletedFocusSessionID"]
        ),
        FlowFixtureDefinition(
            id: "idle_escalation_to_strong_prompt",
            requiredBeforeStateKeys: ["state", "idleSeconds", "riskScore"],
            requiredAfterStateKeys: ["decisionKind", "windowVisible", "quickPromptVisible"]
        ),
        FlowFixtureDefinition(
            id: "calendar_event_write_and_update",
            requiredBeforeStateKeys: ["calendarPermission", "calendarID", "sessionID"],
            requiredAfterStateKeys: ["eventID", "eventWriteStatus", "eventUpdateStatus"]
        ),
        FlowFixtureDefinition(
            id: "reminder_create_edit_complete_delete",
            requiredBeforeStateKeys: ["remindersPermission", "selectedListID", "taskTitle"],
            requiredAfterStateKeys: ["reminderID", "editStatus", "completionStatus", "deleteStatus"]
        )
    ]

    static var canonicalFlowIDs: [String] {
        canonicalFlows.map(\.id)
    }
}
