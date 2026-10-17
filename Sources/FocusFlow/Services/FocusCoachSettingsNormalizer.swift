import Foundation

/// Clamps coach settings to safe ranges. Called before persisting user changes.
/// The six `coach*PromptSeconds` / `coach*EscalationSeconds` fields are no longer read anywhere
/// (audit P2), so they are not normalized either; the stored columns stay for migration safety.
enum FocusCoachSettingsNormalizer {
    static func normalize(_ settings: inout AppSettings) {
        settings.coachPromptBudgetPerSession = min(max(settings.coachPromptBudgetPerSession, 1), 8)
        settings.coachDefaultSnoozeMinutes = min(max(settings.coachDefaultSnoozeMinutes, 5), 30)
        settings.coachMaxStrongPromptsPerSession = min(max(settings.coachMaxStrongPromptsPerSession, 1), 6)
        settings.coachMaxPromptsPerDay = min(max(settings.coachMaxPromptsPerDay, 0), 10)
        settings.coachQuietStartMinute = min(max(settings.coachQuietStartMinute, 0), 1439)
        settings.coachQuietEndMinute = min(max(settings.coachQuietEndMinute, 0), 1439)

        if FocusCoachInterventionMode(rawValue: settings.coachInterventionModeRawValue) == nil {
            settings.coachInterventionModeRawValue = FocusCoachInterventionMode.balanced.rawValue
        }
    }
}
