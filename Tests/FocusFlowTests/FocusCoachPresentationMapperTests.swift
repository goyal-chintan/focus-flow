import XCTest
@testable import FocusFlow

final class FocusCoachPresentationMapperTests: XCTestCase {

    func testStableMapsToGreenStrip() {
        let model = FocusCoachPresentationMapper.map(level: .stable, score: 0.1)
        XCTAssertEqual(model.tone, .green)
        XCTAssertTrue(model.title.contains("Stable"))
        XCTAssertNil(model.subtitle)
    }

    func testDriftRiskMapsToAmberStrip() {
        let model = FocusCoachPresentationMapper.map(level: .driftRisk, score: 0.5)
        XCTAssertEqual(model.tone, .amber)
        XCTAssertTrue(model.title.contains("Drift"))
    }

    func testHighRiskMapsToRedStripAndStrongCopy() {
        let model = FocusCoachPresentationMapper.map(level: .highRisk, score: 0.9)
        XCTAssertEqual(model.tone, .red)
        XCTAssertTrue(model.title.contains("Drift"))
        XCTAssertNotNil(model.subtitle)
    }

    func testQuickPromptDecisionMapsToPromptModel() {
        let decision = FocusCoachDecision(
            kind: .quickPrompt,
            suggestedActions: [.returnNow, .snooze10m],
            message: "Drift detected — quick recovery?"
        )
        let model = FocusCoachPresentationMapper.mapDecision(decision)
        XCTAssertNotNil(model)
        XCTAssertFalse(model!.isStrong)
        XCTAssertEqual(model!.actions.count, 2)
    }

    func testStrongPromptDecisionMapsWithStrongFlag() {
        let decision = FocusCoachDecision(
            kind: .strongPrompt,
            suggestedActions: [.returnNow, .cleanRestart5m, .snooze10m],
            message: "Sustained drift"
        )
        let model = FocusCoachPresentationMapper.mapDecision(decision)
        XCTAssertNotNil(model)
        XCTAssertTrue(model!.isStrong)
        XCTAssertEqual(model!.actions.count, 3)
    }

    func testNoneDecisionReturnsNil() {
        let model = FocusCoachPresentationMapper.mapDecision(.none)
        XCTAssertNil(model)
    }

    func testSoftStripDecisionReturnsNil() {
        let decision = FocusCoachDecision(kind: .softStrip, suggestedActions: [], message: nil)
        let model = FocusCoachPresentationMapper.mapDecision(decision)
        XCTAssertNil(model)
    }
}
