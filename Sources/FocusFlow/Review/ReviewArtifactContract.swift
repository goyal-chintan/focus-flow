import Foundation

enum ReviewArtifactAppearance: String, CaseIterable {
    case light
    case dark
}

enum ReviewArtifactContract {
    /// Required rendered evidence captures per review run.
    static let requiredFlowIDs: [String] = [
        "menu_bar_idle",
        "menu_bar_focusing",
        "menu_bar_paused",
        "menu_bar_overtime",
        "menu_bar_break_overrun",
        "session_complete_focus_complete",
        "session_complete_manual_stop",
        "session_complete_break_complete",
        "session_complete_earned_stage",
        "session_complete_recovery_chips",
        "coach_quick_prompt",
        "coach_strong_window",
        "coach_window_dismiss",
        "settings_calendar_permissions",
        "settings_reminders_permissions",
        "today_stats_view",
        "break_complete_reason_sheet_hidden",
        "break_complete_reason_sheet_visible"
    ]

    static func requiredArtifactPaths(
        runID: String,
        appearance: ReviewArtifactAppearance
    ) -> [String] {
        requiredFlowIDs.map { flowID in
            "Artifacts/review/\(runID)/\(appearance.rawValue)/\(flowID).png"
        }
    }
}
