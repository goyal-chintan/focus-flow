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

    func testPromptCopyComesFromComposer() {
        let composed = CoachMessageComposer.compose(CoachComposerInput(
            style: .gentle,
            trigger: .startNudge,
            facts: CoachFacts(),
            target: CoachStartTarget(minutes: 25, name: "FocusFlow")
        ))
        let decision = FocusCoachDecision(kind: .strongPrompt, suggestedActions: [.startFocusNow], message: nil, composed: composed)
        let model = FocusCoachPresentationMapper.mapDecision(decision)
        XCTAssertEqual(model?.title, "Ready for FocusFlow?")
        XCTAssertEqual(model?.primaryTitle, "Start 25m on FocusFlow")
        XCTAssertFalse(model?.title.contains("Guardrail") ?? true, "v1 fallback titles are retired")
    }
}
