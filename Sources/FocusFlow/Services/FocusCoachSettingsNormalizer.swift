import Foundation

/// Clamps coach settings to safe ranges. Called before persisting user changes.
enum FocusCoachSettingsNormalizer {
    static func normalize(_ settings: inout AppSettings) {
        settings.coachPromptBudgetPerSession = min(max(settings.coachPromptBudgetPerSession, 1), 8)
        settings.coachDefaultSnoozeMinutes = min(max(settings.coachDefaultSnoozeMinutes, 5), 30)
        settings.coachMaxStrongPromptsPerSession = min(max(settings.coachMaxStrongPromptsPerSession, 1), 6)
        if FocusCoachInterventionMode(rawValue: settings.coachInterventionModeRawValue) == nil {
            settings.coachInterventionModeRawValue = FocusCoachInterventionMode.balanced.rawValue
        }
    }
}
