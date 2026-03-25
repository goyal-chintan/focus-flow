import Foundation

/// Clamps coach settings to safe ranges. Called before persisting user changes.
enum FocusCoachSettingsNormalizer {
    static func normalize(_ settings: inout AppSettings) {
        settings.coachPromptBudgetPerSession = min(max(settings.coachPromptBudgetPerSession, 1), 8)
        settings.coachDefaultSnoozeMinutes = min(max(settings.coachDefaultSnoozeMinutes, 5), 30)
        settings.coachMaxStrongPromptsPerSession = min(max(settings.coachMaxStrongPromptsPerSession, 1), 6)

        settings.coachPassivePromptSeconds = min(max(settings.coachPassivePromptSeconds, 15), 300)
        settings.coachAdaptivePromptSeconds = min(max(settings.coachAdaptivePromptSeconds, 15), 300)
        settings.coachStrictPromptSeconds = min(max(settings.coachStrictPromptSeconds, 15), 300)

        settings.coachPassiveEscalationSeconds = min(max(settings.coachPassiveEscalationSeconds, 30), 600)
        settings.coachAdaptiveEscalationSeconds = min(max(settings.coachAdaptiveEscalationSeconds, 30), 600)
        settings.coachStrictEscalationSeconds = min(max(settings.coachStrictEscalationSeconds, 30), 600)

        settings.coachPassiveEscalationSeconds = max(settings.coachPassiveEscalationSeconds, settings.coachPassivePromptSeconds)
        settings.coachAdaptiveEscalationSeconds = max(settings.coachAdaptiveEscalationSeconds, settings.coachAdaptivePromptSeconds)
        settings.coachStrictEscalationSeconds = max(settings.coachStrictEscalationSeconds, settings.coachStrictPromptSeconds)

        if FocusCoachInterventionMode(rawValue: settings.coachInterventionModeRawValue) == nil {
            settings.coachInterventionModeRawValue = FocusCoachInterventionMode.balanced.rawValue
        }
    }
}
