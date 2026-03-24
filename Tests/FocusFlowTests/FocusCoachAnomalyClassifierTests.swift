import XCTest
@testable import FocusFlow

final class FocusCoachAnomalyClassifierTests: XCTestCase {

    let classifier = FocusCoachAnomalyClassifier()

    // MARK: - Break Overrun

    func testBreakOverrunTriggersReasonPrompt() {
        XCTAssertTrue(classifier.shouldPromptReason(event: .breakOverrun(seconds: 180)))
    }

    func testShortBreakOverrunDoesNotTrigger() {
        XCTAssertFalse(classifier.shouldPromptReason(event: .breakOverrun(seconds: 60)))
    }

    // MARK: - Pause

    func testShortPauseDoesNotTriggerReasonPrompt() {
        XCTAssertFalse(classifier.shouldPromptReason(event: .pause(seconds: 30)))
    }

    func testLongPauseTriggersReasonPrompt() {
        XCTAssertTrue(classifier.shouldPromptReason(event: .pause(seconds: 150)))
    }

    // MARK: - Mid-Session Stop

    func testMidSessionStopAt50PercentTriggers() {
        XCTAssertTrue(classifier.shouldPromptReason(event: .midSessionStop(elapsedSeconds: 750, totalSeconds: 1500)))
    }

    func testMidSessionStopAt95PercentDoesNotTrigger() {
        XCTAssertFalse(classifier.shouldPromptReason(event: .midSessionStop(elapsedSeconds: 1425, totalSeconds: 1500)))
    }

    func testMidSessionStopAt5PercentDoesNotTrigger() {
        XCTAssertFalse(classifier.shouldPromptReason(event: .midSessionStop(elapsedSeconds: 75, totalSeconds: 1500)))
    }

    // MARK: - Repeated Drift

    func testRepeatedDriftTriggersAfterThreshold() {
        XCTAssertTrue(classifier.shouldPromptReason(event: .repeatedDrift(consecutiveHighRiskWindows: 4)))
    }

    func testSingleDriftWindowDoesNotTrigger() {
        XCTAssertFalse(classifier.shouldPromptReason(event: .repeatedDrift(consecutiveHighRiskWindows: 1)))
    }

    // MARK: - Fake Start

    func testFakeStartTriggersAfterThreshold() {
        XCTAssertTrue(classifier.shouldPromptReason(event: .fakeStart(idleAfterStartSeconds: 90)))
    }

    func testQuickStartDoesNotTrigger() {
        XCTAssertFalse(classifier.shouldPromptReason(event: .fakeStart(idleAfterStartSeconds: 30)))
    }

    // MARK: - Interruption Kind Mapping

    func testInterruptionKindMapping() {
        XCTAssertEqual(classifier.interruptionKind(for: .breakOverrun(seconds: 120)), .breakOverrun)
        XCTAssertEqual(classifier.interruptionKind(for: .midSessionStop(elapsedSeconds: 500, totalSeconds: 1000)), .midSessionStop)
        XCTAssertEqual(classifier.interruptionKind(for: .fakeStart(idleAfterStartSeconds: 60)), .fakeStart)
        XCTAssertEqual(classifier.interruptionKind(for: .repeatedDrift(consecutiveHighRiskWindows: 3)), .drift)
        XCTAssertEqual(classifier.interruptionKind(for: .pause(seconds: 120)), .drift)
    }
}
