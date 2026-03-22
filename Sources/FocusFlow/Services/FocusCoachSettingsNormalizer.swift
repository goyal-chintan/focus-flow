import Foundation

/// Clamps coach settings to safe ranges. Called before persisting user changes.
enum FocusCoachSettingsNormalizer {
    static func normalize(_ settings: inout AppSettings) {
        settings.coachPromptBudgetPerSession = min(max(settings.coachPromptBudgetPerSession, 1), 8)
        settings.coachDefaultSnoozeMinutes = min(max(settings.coachDefaultSnoozeMinutes, 5), 30)
    }
}
