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
}
