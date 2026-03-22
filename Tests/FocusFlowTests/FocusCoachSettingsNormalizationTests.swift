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
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachPromptBudgetPerSession, 4)
        XCTAssertEqual(settings.coachDefaultSnoozeMinutes, 10)
    }
}
