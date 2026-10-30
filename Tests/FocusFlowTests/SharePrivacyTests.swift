import XCTest
import SwiftData
@testable import FocusFlow

/// Hide while sharing my screen (2026-10-30): nothing on screen names FocusFlow or your work while
/// the screen is shared, and the block-end window waits until the share is over.
@MainActor
final class SharePrivacyTests: XCTestCase {
    private var container: ModelContainer?
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Only an actual share (or "Private now") hides FocusFlow; being in a meeting does not.
    func testOnlySharingOrManualMakesItPrivate() {
        XCTAssertFalse(SharePrivacy.isPrivate(.init(), lastSharedAt: nil, now: now))
        XCTAssertTrue(SharePrivacy.isPrivate(.init(manual: true), lastSharedAt: nil, now: now))
        XCTAssertTrue(SharePrivacy.isPrivate(.init(screenShared: true), lastSharedAt: nil, now: now))
    }

    func testABriefHoldAfterTheShareEndsAvoidsFlicker() {
        XCTAssertTrue(SharePrivacy.isPrivate(.init(), lastSharedAt: now.addingTimeInterval(-2), now: now))
        XCTAssertFalse(SharePrivacy.isPrivate(.init(), lastSharedAt: now.addingTimeInterval(-SharePrivacy.holdSeconds - 1), now: now))
    }

    /// Measured 2026-10-30 (macOS 26, Zoom): the private signal is present; it reads false here
    /// because nothing captures the screen while tests run.
    func testScreenCaptureSignalIsReadable() {
        _ = ScreenCapture.isActive
    }

    private func makeVM() throws -> TimerViewModel {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self,
                             AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self,
                             IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self,
                             GoalProgressEntry.self, DailyTask.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        self.container = container
        let vm = TimerViewModel()
        vm.systemIdleSecondsProvider = { 0 }
        vm.coachExploreSizes = false
        vm.configure(modelContext: container.mainContext)
        return vm
    }

    func testSharingHoldsTheBlockEndWindowAndPanelsThenOpensTheWindowAfter() throws {
        let vm = try makeVM()
        defer {
            AppUsageTracker.shared.stop()
            NotificationService.shared.isPrivate = false
        }
        var share = SharePrivacy.Signals(screenShared: true)
        vm.shareSignalsProvider = { share }
        var opened = 0
        vm.openCompletionWindow = { opened += 1 }

        vm.refreshPrivacy(now: now)
        XCTAssertTrue(vm.isPrivate)
        XCTAssertTrue(NotificationService.shared.isPrivate, "No banners or sounds while sharing")

        vm.showSessionComplete = true
        vm.showCompletionWindow()
        XCTAssertEqual(opened, 0, "The block-end window waits")

        vm.presentCoachPanel(CoachPanelPresentation(kind: .notice, message: CoachMessageComposer.compose(CoachComposerInput(
            style: .challenger, trigger: .starterStarted(minutes: 5), facts: CoachFacts(), target: CoachStartTarget(minutes: 5, name: nil)
        ))))
        XCTAssertNil(vm.coachPanel, "No coach panel while sharing")

        share = .init()
        vm.refreshPrivacy(now: now.addingTimeInterval(2))
        XCTAssertTrue(vm.isPrivate, "Still within the hold")
        vm.refreshPrivacy(now: now.addingTimeInterval(SharePrivacy.holdSeconds + 1))
        XCTAssertFalse(vm.isPrivate)
        XCTAssertFalse(NotificationService.shared.isPrivate)
        XCTAssertEqual(opened, 1, "Opens once the share is over")
    }

    func testPrivateNowWorksEvenWithTheAutomaticSettingOff() throws {
        let vm = try makeVM()
        defer {
            AppUsageTracker.shared.stop()
            NotificationService.shared.isPrivate = false
        }
        vm.settings?.coachSuppressPopupsDuringScreenShare = false
        vm.setPrivateManually(true)
        XCTAssertTrue(vm.isPrivate)
        vm.setPrivateManually(false)
        XCTAssertFalse(vm.isPrivate)
    }
}
