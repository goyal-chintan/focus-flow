import XCTest
@testable import FocusFlow

final class CoachPseudoProductivityGuardTests: XCTestCase {
    private let now = Date()

    private func input(_ edit: (inout CoachPseudoProductivityGuard.Input) -> Void = { _ in }) -> CoachPseudoProductivityGuard.Input {
        var input = CoachPseudoProductivityGuard.Input(
            now: now,
            inGoodWindow: true,
            sessionActive: false,
            pacing: CoachGoalPacing(goalMinutes: 120, doneMinutes: 30, windowMinutesLeft: 120),
            contextRunStart: now.addingTimeInterval(-25 * 60),
            lastAskedAt: nil,
            hasPriority: true
        )
        edit(&input)
        return input
    }

    func testAsksInsideWindowAfterTwentyMinutesOfWorkContextWhenBehind() {
        XCTAssertTrue(CoachPseudoProductivityGuard.shouldAsk(input()))
    }

    func testEachConditionIsRequired() {
        XCTAssertFalse(CoachPseudoProductivityGuard.shouldAsk(input { $0.contextRunStart = self.now.addingTimeInterval(-19 * 60) }))
        XCTAssertFalse(CoachPseudoProductivityGuard.shouldAsk(input { $0.contextRunStart = nil }))
        XCTAssertFalse(CoachPseudoProductivityGuard.shouldAsk(input { $0.inGoodWindow = false }))
        XCTAssertFalse(CoachPseudoProductivityGuard.shouldAsk(input { $0.sessionActive = true }))
        XCTAssertFalse(CoachPseudoProductivityGuard.shouldAsk(input { $0.hasPriority = false }))
        XCTAssertFalse(CoachPseudoProductivityGuard.shouldAsk(input {
            $0.pacing = CoachGoalPacing(goalMinutes: 120, doneMinutes: 90, windowMinutesLeft: 120)
        }), "Pressure 0.25 is on track")
    }

    func testAsksOnlyOncePerWindow() {
        XCTAssertFalse(CoachPseudoProductivityGuard.shouldAsk(input { $0.lastAskedAt = self.now.addingTimeInterval(-2 * 3600) }))
        XCTAssertTrue(CoachPseudoProductivityGuard.shouldAsk(input { $0.lastAskedAt = self.now.addingTimeInterval(-4 * 3600) }))
    }

    func testContextRunTracking() {
        let start = now.addingTimeInterval(-600)
        XCTAssertEqual(CoachPseudoProductivityGuard.updatedRunStart(previous: nil, category: .productive, sessionActive: false, now: now), now)
        XCTAssertEqual(CoachPseudoProductivityGuard.updatedRunStart(previous: start, category: .neutral, sessionActive: false, now: now), start,
                       "Cursor → Claude keeps the run going")
        XCTAssertNil(CoachPseudoProductivityGuard.updatedRunStart(previous: start, category: .distracting, sessionActive: false, now: now))
        XCTAssertNil(CoachPseudoProductivityGuard.updatedRunStart(previous: start, category: .productive, sessionActive: true, now: now))
    }

    func testAnswerLogKeepsSideQuestRate() throws {
        let suite = "CoachPseudoLog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { TestDefaults.remove(suite) }
        let log = CoachPseudoWorkLog(defaults: defaults)
        for answer in [CoachPseudoAnswer.sideQuest, .sideQuest, .isPriority, .planned] {
            log.append(CoachPseudoWorkEntry(answeredAt: now, answer: answer, contextName: "Claude", hourOfDay: 22, priorityTitle: "Ship v1"))
        }
        XCTAssertEqual(log.entries.count, 4)
        XCTAssertEqual(log.sideQuestRate(contextName: "Claude") ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertNil(log.sideQuestRate(contextName: "Cursor"))
    }
}
