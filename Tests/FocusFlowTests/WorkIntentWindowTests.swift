import Testing
import Foundation
@testable import FocusFlow

@Suite("WorkIntentWindow — Outside-Session Challenge Gate")
struct WorkIntentWindowTests {

    let detector = WorkIntentWindowDetector()

    @Test("No work intent signals → not a work intent window")
    func noSignalsNotWorkIntentWindow() {
        let signal = detector.evaluate(
            appLastOpenedAt: nil,
            projectLastSelectedAt: nil,
            lastAbandonedStartAt: nil,
            matchesHistoricalMissedStart: false,
            currentHour: 22,
            historicalWorkHours: 9...18
        )
        #expect(signal.isWorkIntentWindow == false)
    }

    @Test("Only 1 signal → not a work intent window (requires 2+)")
    func oneSignalNotSufficient() {
        let recentTime = Date().addingTimeInterval(-5 * 60)  // 5 min ago
        let signal = detector.evaluate(
            appLastOpenedAt: recentTime,
            projectLastSelectedAt: nil,
            lastAbandonedStartAt: nil,
            matchesHistoricalMissedStart: false,
            currentHour: 22,
            historicalWorkHours: 9...18
        )
        #expect(signal.isWorkIntentWindow == false)
    }

    @Test("App opened recently + within work hours = work intent window")
    func appOpenedAndWorkHoursIsWorkIntent() {
        let recentTime = Date().addingTimeInterval(-5 * 60)
        let signal = detector.evaluate(
            appLastOpenedAt: recentTime,
            projectLastSelectedAt: nil,
            lastAbandonedStartAt: nil,
            matchesHistoricalMissedStart: false,
            currentHour: 14,
            historicalWorkHours: 9...18
        )
        #expect(signal.openedAppRecently == true)
        #expect(signal.withinTypicalWorkHours == true)
        #expect(signal.isWorkIntentWindow == true)
    }

    @Test("Abandoned start + project selected recently = work intent window")
    func abandonedAndProjectSelectedIsWorkIntent() {
        let recentTime = Date().addingTimeInterval(-3 * 60)
        let signal = detector.evaluate(
            appLastOpenedAt: nil,
            projectLastSelectedAt: recentTime,
            lastAbandonedStartAt: recentTime,
            matchesHistoricalMissedStart: false,
            currentHour: 22,
            historicalWorkHours: 9...18
        )
        #expect(signal.selectedProjectRecently == true)
        #expect(signal.recentlyAbandonedStart == true)
        #expect(signal.isWorkIntentWindow == true)
    }

    @Test("Outside-session challenge suppressed when not in work intent window")
    func challengeSuppressedOutsideWorkIntent() {
        let planner = FocusCoachInterventionPlanner()
        let noWorkIntent = WorkIntentSignal(
            openedAppRecently: false,
            selectedProjectRecently: false,
            recentlyAbandonedStart: false,
            withinTypicalWorkHours: false,
            matchesHistoricalMissedStart: false
        )

        let shouldChallenge = planner.shouldTriggerOutsideSessionChallenge(
            guardianState: .challenge,
            isInReleaseWindow: false,
            workIntentSignal: noWorkIntent,
            hasHighConfidenceDrift: true,
            repeatedProjectPattern: false,
            engagementMode: .adaptive
        )
        #expect(shouldChallenge == false)
    }

    @Test("Outside-session challenge fires when all gates pass")
    func challengeFiresWhenAllGatesPass() {
        let planner = FocusCoachInterventionPlanner()
        let workIntent = WorkIntentSignal(
            openedAppRecently: true,
            selectedProjectRecently: true,
            recentlyAbandonedStart: false,
            withinTypicalWorkHours: false,
            matchesHistoricalMissedStart: false
        )

        let shouldChallenge = planner.shouldTriggerOutsideSessionChallenge(
            guardianState: .challenge,
            isInReleaseWindow: false,
            workIntentSignal: workIntent,
            hasHighConfidenceDrift: true,
            repeatedProjectPattern: false,
            engagementMode: .adaptive
        )
        #expect(shouldChallenge == true)
    }

    @Test("Release window always suppresses outside-session challenge")
    func releaseWindowSuppressesChallenge() {
        let planner = FocusCoachInterventionPlanner()
        let strongWorkIntent = WorkIntentSignal(
            openedAppRecently: true,
            selectedProjectRecently: true,
            recentlyAbandonedStart: true,
            withinTypicalWorkHours: true,
            matchesHistoricalMissedStart: true
        )

        let shouldChallenge = planner.shouldTriggerOutsideSessionChallenge(
            guardianState: .challenge,
            isInReleaseWindow: true,
            workIntentSignal: strongWorkIntent,
            hasHighConfidenceDrift: true,
            repeatedProjectPattern: true,
            engagementMode: .adaptive
        )
        #expect(shouldChallenge == false)
    }

    @Test("Passive engagement mode always suppresses outside-session challenge")
    func passiveModeSuppressesChallenge() {
        let planner = FocusCoachInterventionPlanner()
        let workIntent = WorkIntentSignal(
            openedAppRecently: true,
            selectedProjectRecently: true,
            recentlyAbandonedStart: false,
            withinTypicalWorkHours: false,
            matchesHistoricalMissedStart: false
        )

        let shouldChallenge = planner.shouldTriggerOutsideSessionChallenge(
            guardianState: .challenge,
            isInReleaseWindow: false,
            workIntentSignal: workIntent,
            hasHighConfidenceDrift: true,
            repeatedProjectPattern: false,
            engagementMode: .passive
        )
        #expect(shouldChallenge == false)
    }

    @Test("Historical missed-start input is wired through evaluate")
    func historicalMissedStartSignalIsWired() {
        let signal = detector.evaluate(
            appLastOpenedAt: nil,
            projectLastSelectedAt: nil,
            lastAbandonedStartAt: nil,
            matchesHistoricalMissedStart: true,
            currentHour: 22,
            historicalWorkHours: 9...18
        )
        #expect(signal.matchesHistoricalMissedStart == true)
        #expect(signal.isWorkIntentWindow == false, "A lone historical signal should not pass 2-signal gate")
    }

    @Test("Outside-session challenge requires high drift OR repeated project pattern")
    func challengeRequiresConfidenceOrRepeatedPattern() {
        let planner = FocusCoachInterventionPlanner()
        let workIntent = WorkIntentSignal(
            openedAppRecently: true,
            selectedProjectRecently: true,
            recentlyAbandonedStart: false,
            withinTypicalWorkHours: false,
            matchesHistoricalMissedStart: false
        )

        let shouldChallenge = planner.shouldTriggerOutsideSessionChallenge(
            guardianState: .challenge,
            isInReleaseWindow: false,
            workIntentSignal: workIntent,
            hasHighConfidenceDrift: false,
            repeatedProjectPattern: false,
            engagementMode: .adaptive
        )
        #expect(shouldChallenge == false)
    }
}
