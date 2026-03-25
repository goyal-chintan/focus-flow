import XCTest
@testable import FocusFlow

final class EarnedBreakSuggestionEngineTests: XCTestCase {
    func test55MinuteEffortSuggests15Minutes() {
        let engine = EarnedBreakSuggestionEngine()
        let input = EarnedBreakSuggestionInput(
            effectiveEffortSeconds: 55 * 60,
            overtimeSeconds: 0,
            runCreditSeconds: 55 * 60,
            adaptationMinutes: 0
        )

        XCTAssertEqual(engine.suggest(input).suggestedMinutes, 15)
    }

    func testOvertimeBonusCapsAt20Minutes() {
        let engine = EarnedBreakSuggestionEngine()
        let input = EarnedBreakSuggestionInput(
            effectiveEffortSeconds: 90 * 60,
            overtimeSeconds: 15 * 60,
            runCreditSeconds: 90 * 60,
            adaptationMinutes: 0
        )

        XCTAssertEqual(engine.suggest(input).suggestedMinutes, 20)
    }

    func testAdaptationIsClampedBetweenMinus3AndPlus3() {
        let engine = EarnedBreakSuggestionEngine()
        let input = EarnedBreakSuggestionInput(
            effectiveEffortSeconds: 40 * 60,
            overtimeSeconds: 0,
            runCreditSeconds: 40 * 60,
            adaptationMinutes: 9
        )

        XCTAssertEqual(engine.suggest(input).adaptationAppliedMinutes, 3)
    }
}
