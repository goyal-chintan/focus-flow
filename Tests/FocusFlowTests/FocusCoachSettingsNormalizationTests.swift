import XCTest
@testable import FocusFlow

final class FocusCoachSettingsNormalizationTests: XCTestCase {

    func testPromptBudgetIsClamped() {
        var settings = AppSettings()
        settings.coachPromptBudgetPerSession = 99
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachPromptBudgetPerSession, 8)
    }

    func testPromptBudgetMinimumIsClamped() {
        var settings = AppSettings()
        settings.coachPromptBudgetPerSession = 0
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachPromptBudgetPerSession, 1)
    }

    func testSnoozeDurationIsClamped() {
        var settings = AppSettings()
        settings.coachDefaultSnoozeMinutes = 60
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachDefaultSnoozeMinutes, 30)
    }

    func testSnoozeDurationMinimumIsClamped() {
        var settings = AppSettings()
        settings.coachDefaultSnoozeMinutes = 1
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachDefaultSnoozeMinutes, 5)
    }

    func testValidSettingsUnchanged() {
        var settings = AppSettings()
        settings.coachPromptBudgetPerSession = 4
        settings.coachDefaultSnoozeMinutes = 10
        settings.coachMaxStrongPromptsPerSession = 2
        settings.coachInterventionModeRawValue = FocusCoachInterventionMode.adaptiveStrict.rawValue
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachPromptBudgetPerSession, 4)
        XCTAssertEqual(settings.coachDefaultSnoozeMinutes, 10)
        XCTAssertEqual(settings.coachMaxStrongPromptsPerSession, 2)
        XCTAssertEqual(settings.coachInterventionMode, .adaptiveStrict)
    }

    func testMaxStrongPromptsPerSessionIsClamped() {
        var settings = AppSettings()
        settings.coachMaxStrongPromptsPerSession = 99
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachMaxStrongPromptsPerSession, 6)
    }

    func testMaxStrongPromptsPerSessionMinimumIsClamped() {
        var settings = AppSettings()
        settings.coachMaxStrongPromptsPerSession = 0
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachMaxStrongPromptsPerSession, 1)
    }

    func testInvalidInterventionModeFallsBackToBalanced() {
        var settings = AppSettings()
        settings.coachInterventionModeRawValue = "unknown-mode"
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachInterventionMode, .balanced)
    }

    func testGuardianCadenceDefaultsAreSet() {
        let settings = AppSettings()
        XCTAssertTrue(settings.coachSuppressPopupsDuringScreenShare)
        XCTAssertEqual(settings.coachPassivePromptSeconds, 120)
        XCTAssertEqual(settings.coachPassiveEscalationSeconds, 240)
        XCTAssertEqual(settings.coachAdaptivePromptSeconds, 90)
        XCTAssertEqual(settings.coachAdaptiveEscalationSeconds, 180)
        XCTAssertEqual(settings.coachStrictPromptSeconds, 60)
        XCTAssertEqual(settings.coachStrictEscalationSeconds, 120)
    }

    func testCadencePromptsAreClampedToRange() {
        var settings = AppSettings()
        settings.coachPassivePromptSeconds = 5
        settings.coachAdaptivePromptSeconds = 500
        settings.coachStrictPromptSeconds = 14

        FocusCoachSettingsNormalizer.normalize(&settings)

        XCTAssertEqual(settings.coachPassivePromptSeconds, 15)
        XCTAssertEqual(settings.coachAdaptivePromptSeconds, 300)
        XCTAssertEqual(settings.coachStrictPromptSeconds, 15)
    }

    func testCadenceEscalationsAreClampedToRange() {
        var settings = AppSettings()
        settings.coachPassivePromptSeconds = 15
        settings.coachAdaptivePromptSeconds = 15
        settings.coachStrictPromptSeconds = 15
        settings.coachPassiveEscalationSeconds = 5
        settings.coachAdaptiveEscalationSeconds = 900
        settings.coachStrictEscalationSeconds = 29

        FocusCoachSettingsNormalizer.normalize(&settings)

        XCTAssertEqual(settings.coachPassiveEscalationSeconds, 30)
        XCTAssertEqual(settings.coachAdaptiveEscalationSeconds, 600)
        XCTAssertEqual(settings.coachStrictEscalationSeconds, 30)
    }

    func testCadenceEscalationIsNeverBelowPrompt() {
        var settings = AppSettings()
        settings.coachPassivePromptSeconds = 180
        settings.coachPassiveEscalationSeconds = 120
        settings.coachAdaptivePromptSeconds = 240
        settings.coachAdaptiveEscalationSeconds = 90
        settings.coachStrictPromptSeconds = 120
        settings.coachStrictEscalationSeconds = 60

        FocusCoachSettingsNormalizer.normalize(&settings)

        XCTAssertEqual(settings.coachPassiveEscalationSeconds, settings.coachPassivePromptSeconds)
        XCTAssertEqual(settings.coachAdaptiveEscalationSeconds, settings.coachAdaptivePromptSeconds)
        XCTAssertEqual(settings.coachStrictEscalationSeconds, settings.coachStrictPromptSeconds)
    }
}
