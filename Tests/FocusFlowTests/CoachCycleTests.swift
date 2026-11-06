import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v7 (docs/plans/2026-11-06-coach-v7-land-and-return.md): land the block, return from the break.
final class CoachCycleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    // MARK: Landing

    func testOvertimeNudgesAt5AndResurfacesAt10UnlessALapWasChosen() {
        XCTAssertEqual(CoachLanding.overtimeStep(overtimeSeconds: 299, lapEndsAt: nil), .none)
        XCTAssertEqual(CoachLanding.overtimeStep(overtimeSeconds: 300, lapEndsAt: nil), .stretchNudge)
        XCTAssertEqual(CoachLanding.overtimeStep(overtimeSeconds: 600, lapEndsAt: nil), .resurface)
        XCTAssertEqual(CoachLanding.overtimeStep(overtimeSeconds: 300, lapEndsAt: 690), .none, "A chosen lap is left alone")
        XCTAssertEqual(CoachLanding.overtimeStep(overtimeSeconds: 690, lapEndsAt: 690), .lapEnded)
    }

    // MARK: Return ladder

    func testReturnLadderSteps() {
        XCTAssertEqual(CoachReturnLadder.step(overrunSeconds: 180, reentrySeconds: 600), .none)
        XCTAssertEqual(CoachReturnLadder.step(overrunSeconds: 600, reentrySeconds: 600), .reentry)
        XCTAssertEqual(CoachReturnLadder.step(overrunSeconds: 1800, reentrySeconds: 600), .close)
        XCTAssertEqual(CoachReturnLadder.sizes(regular: 25, reentry: false), [25, 10])
        XCTAssertEqual(CoachReturnLadder.sizes(regular: 10, reentry: false), [10])
        XCTAssertEqual(CoachReturnLadder.sizes(regular: 25, reentry: true), [5])
    }

    // MARK: Learner A: return hazard

    func testHazardFindsWhereReturnsStopHappeningOnTheirOwn() {
        // Half the breaks end with a start in the first 2 minutes; the rest drag past 30 or never.
        let latencies: [Double?] = Array(repeating: 1, count: 10) + Array(repeating: 35, count: 4) + Array(repeating: nil, count: 6)
        let hazard = CoachReturnHazard.fit(latencies: latencies)
        XCTAssertEqual(hazard.episodes, 20)
        XCTAssertGreaterThan(hazard.hazard[0], hazard.hazard[1] * 2, "Returns happen early or not at all")
        XCTAssertEqual(hazard.reentryMinute, 3, "The re-entry offer moves to where the hazard collapses")
        XCTAssertGreaterThan(hazard.startedWithin(5), 0.4)
        XCTAssertLessThan(hazard.startedWithin(5), 0.6)
    }

    func testHazardKeepsTheDefaultUntilThereAreEnoughBreaks() {
        XCTAssertEqual(CoachReturnHazard.fit(latencies: [1, 2, nil]).reentryMinute, 10)
    }

    func testHazardTreatsLateStartsAsCensored() {
        let late = CoachReturnHazard.fit(latencies: Array(repeating: 200, count: 10))
        let never = CoachReturnHazard.fit(latencies: Array(repeating: nil, count: 10))
        XCTAssertEqual(late, never)
    }

    // MARK: Learner B: the randomised return panel

    func testReturnPanelLiftIsEstimatedWithInversePropensityWeights() {
        var decisions: [CoachCycleExperiment.Decision] = []
        var starts: [Date] = []
        for i in 0..<30 {
            let at = minutes(Double(i) * 120)
            let treated = i % 10 < 7
            decisions.append(.init(at: at, treated: treated, propensity: 0.7))
            // Treated: back in 3 min 6 of 7 times; control: 1 of 3.
            if treated ? (i % 10 != 6) : (i % 10 == 7) { starts.append(at.addingTimeInterval(180)) }
        }
        let estimate = try! XCTUnwrap(CoachCycleExperiment.estimate(decisions, starts: starts, now: minutes(4000)))
        XCTAssertEqual(estimate.decisions, 30)
        XCTAssertEqual(estimate.treatedRate, 6.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(estimate.controlRate, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertNil(CoachCycleExperiment.estimate(Array(decisions.prefix(10)), starts: starts, now: minutes(4000)), "Needs 20 decisions")
    }

    // MARK: Cycle stats

    private func block(at start: Double, planned: Double, active: Double, paused: Double = 0) -> CoachCycleStats.Session {
        .init(isFocus: true, start: minutes(start), end: minutes(start + active + paused), plannedSeconds: planned * 60, pausedSeconds: paused * 60)
    }

    func testStretchFactComparesTheGapAfterStretchedAndOnTimeBlocks() {
        var sessions: [CoachCycleStats.Session] = []
        var clock = 0.0
        for i in 0..<10 {
            let stretched = i % 2 == 0
            let active = stretched ? 37.0 : 25.0
            sessions.append(block(at: clock, planned: 25, active: active))
            clock += active + (stretched ? 86 : 24)
        }
        let stats = CoachCycleStats.compute(sessions)
        XCTAssertEqual(stats.blocks, 10)
        XCTAssertEqual(stats.stretchedBlocks, 5)
        XCTAssertEqual(stats.stretchFact, "Blocks you run 5+ min over are followed by a 86-min gap; blocks that end on time, 24 min.")
        XCTAssertNotNil(stats.sentence)
    }

    func testChainedBlocksAndNextSittingsAreNotReturns() {
        let sessions = [block(at: 0, planned: 25, active: 25), block(at: 25.5, planned: 25, active: 25), block(at: 60 * 10, planned: 25, active: 25)]
        XCTAssertTrue(CoachCycleStats.compute(sessions).gaps.isEmpty)
    }

    // MARK: Natural length

    func testNaturalLengthOffersTheLengthYouActuallyWork() {
        let blocks = (0..<10).map { block(at: Double($0) * 120, planned: 25, active: 36) }
        XCTAssertEqual(CoachNaturalLength.suggestion(blocks, regularMinutes: 25), 35)
        let paused = (0..<10).map { block(at: Double($0) * 120, planned: 25, active: 36, paused: 5) }
        XCTAssertNil(CoachNaturalLength.suggestion(paused, regularMinutes: 25), "Pauses are not focus running long")
        let onTime = (0..<10).map { block(at: Double($0) * 120, planned: 25, active: 26) }
        XCTAssertNil(CoachNaturalLength.suggestion(onTime, regularMinutes: 25))
    }

    func testNaturalLengthQuestionWording() {
        let question = CoachQuestion.naturalLength(minutes: 35, regular: 25)
        XCTAssertEqual(question.hook, "Your blocks run about 35 min. Make 35 your usual?")
        XCTAssertEqual(question.choices.map(\.title), ["Make it 35 min", "Keep 25 min"])
    }
}

/// The view-model wiring, on an in-memory store with the real timer.
@MainActor
final class CoachCycleFlowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var vm: TimerViewModel!
    private var settings: AppSettings!

    override func setUp() async throws {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self
        ])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        context = container.mainContext
        settings = AppSettings()
        settings.coachOnScreenPromptsEnabled = true
        settings.coachIdleStarterEnabled = true
        context.insert(settings)
        try context.save()
        vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
    }

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        vm = nil; settings = nil; context = nil; container = nil
        try await super.tearDown()
    }

    func testLandingCueStoresTheNextStepOnTheRunningBlock() {
        vm.selectedMinutes = 25
        XCTAssertTrue(vm.startFocus())
        vm.presentLandingCue()
        XCTAssertEqual(vm.coachPanel?.kind, .landing)
        vm.saveLandingNextStep("Write the join for Q4")
        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(vm.latestNextStep(), "Write the join for Q4")
        vm.presentLandingCue()
        XCTAssertNil(vm.coachPanel, "Once per block")
    }

    func testKeepGoingIsABoundedLap() {
        vm.seedEvidenceCompletionState(sessionType: .focus, project: nil, customLabel: "Write", duration: 1500, overtimeSeconds: 30)
        vm.keepGoingLap()
        XCTAssertTrue(vm.isInOvertimeLap)
        XCTAssertFalse(vm.showSessionComplete)
        vm.continueAfterCompletion(action: .endSession)
        XCTAssertFalse(vm.isInOvertimeLap)
    }

    private func runBreakIntoOverrun() {
        vm.startBreak(overrideDuration: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        XCTAssertTrue(vm.isBreakOvertime)
    }

    func testBreakEndShowsTheReturnPanelAndItStartsTheNextBlock() {
        vm.cycleArmOverride = true
        runBreakIntoOverrun()
        XCTAssertEqual(vm.coachPanel?.kind, .returnFromBreak)
        XCTAssertEqual(vm.coachPanel?.sizeOptions, [vm.regularMinutes, 10])
        XCTAssertTrue(vm.performCoachPanelStart(minutes: 10))
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(Int(vm.totalSeconds), 600)
        XCTAssertNil(vm.coachPanel)
    }

    func testControlArmGetsNoPanel() {
        vm.cycleArmOverride = false
        runBreakIntoOverrun()
        XCTAssertNil(vm.coachPanel)
        XCTAssertFalse(vm.returnLadderTreated)
    }
}
