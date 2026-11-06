import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v8 phase 5 (§3.6): one job per surface.
final class CalmSurfacesTests: XCTestCase {
    private let format: (TimeInterval) -> String = { seconds in
        let minutes = Int(seconds / 60)
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
    }

    private func goal(_ minutes: Int) -> DailyGoal {
        DailyGoal.resolve(scope: .allFocus, targetMinutes: [], fixedSeconds: TimeInterval(minutes * 60), stretchSeconds: TimeInterval(minutes * 60), followsTargets: false)
    }

    // MARK: Today's one sentence

    func testTodaySaysProgressPaceAndDayTypeOnce() {
        XCTAssertEqual(CalmSurfaces.todaySentence(doneSeconds: 103 * 60, goal: goal(150), pace: .onTrack, dayType: .leave, format: format),
                       "1h 43m of 2h 30m · on pace · leave day")
        XCTAssertEqual(CalmSurfaces.todaySentence(doneSeconds: 0, goal: goal(90), pace: .atRisk, dayType: .workday, format: format),
                       "0m of 1h 30m · behind pace", "A workday is not named")
        XCTAssertEqual(CalmSurfaces.todaySentence(doneSeconds: 20 * 60, goal: goal(120), pace: .unknown, dayType: nil, format: format),
                       "20m of 2h", "No window data: no pace claim")
    }

    func testAMetGoalDropsThePaceAndASickDayRests() {
        XCTAssertEqual(CalmSurfaces.todaySentence(doneSeconds: 160 * 60, goal: goal(150), pace: .goalMet, dayType: .weekend, format: format),
                       "2h 40m · goal of 2h 30m met · weekend")
        XCTAssertEqual(CalmSurfaces.todaySentence(doneSeconds: 0, goal: goal(150).sized(minutes: 0, for: .sick), pace: .goalMet, dayType: .sick, format: format),
                       "Sick day · rest")
        XCTAssertEqual(CalmSurfaces.todaySentence(doneSeconds: 25 * 60, goal: goal(150), pace: .onTrack, dayType: .sick, format: format),
                       "Sick day · rest · 25m logged")
    }

    // MARK: Notch: the lever or the task, never both

    func testNotchShowsOneNextAction() {
        XCTAssertEqual(CalmSurfaces.notchNext(inBlock: false, hasTask: true, tasksPlanned: 3, hasLever: true, hasResult: false), .task,
                       "A planned task beats the lever")
        XCTAssertEqual(CalmSurfaces.notchNext(inBlock: false, hasTask: false, tasksPlanned: 0, hasLever: true, hasResult: false), .lever)
        XCTAssertEqual(CalmSurfaces.notchNext(inBlock: false, hasTask: false, tasksPlanned: 3, hasLever: true, hasResult: false), .lever,
                       "All tasks done: the lever, not a finished list")
        XCTAssertEqual(CalmSurfaces.notchNext(inBlock: true, hasTask: true, tasksPlanned: 3, hasLever: true, hasResult: true), .task,
                       "In a block, its own task beats the key result's +1")
        XCTAssertEqual(CalmSurfaces.notchNext(inBlock: true, hasTask: false, tasksPlanned: 3, hasLever: true, hasResult: true), .result)
        XCTAssertEqual(CalmSurfaces.notchNext(inBlock: true, hasTask: false, tasksPlanned: 0, hasLever: true, hasResult: false), .none,
                       "In a block the lever is never shown: the block is already on it")
    }

    func testNotchSnapshotNeverShowsBoth() {
        let lever = DailyLever(id: UUID(), goalTitle: "Interview-ready", projectID: nil, action: "3 LeetCode questions",
                               reason: "need 2.6/day", status: .behind, urgency: 1)
        var snapshot = NotchSnapshot(mode: .onBreak(paused: false), time: "04:21", progress: 0.4, projectName: "Learning", projectColor: nil,
                                     intent: nil, goalDone: 0, goalTarget: 3600, goalLabel: "Own work", lever: lever, coachHook: nil, quickResult: nil,
                                     tasks: DailyTaskStats(planned: 2, done: 0), nextTask: (UUID(), "Window functions"))
        XCTAssertEqual(snapshot.next, .task)
        XCTAssertEqual(snapshot.nextLine, "Window functions")
        snapshot.nextTask = nil
        snapshot.tasks = nil
        XCTAssertEqual(snapshot.nextLine, "3 LeetCode questions")
    }

    func testNotchIntentIsNotRepeatedUnderItsTask() {
        XCTAssertNil(CalmSurfaces.notchIntent("Window functions", taskTitle: "window functions"))
        XCTAssertEqual(CalmSurfaces.notchIntent("Draft the intro", taskTitle: "Window functions"), "Draft the intro")
        XCTAssertNil(CalmSurfaces.notchIntent("  ", taskTitle: nil))
    }

    // MARK: Goals: "today: …"

    func testGoalTodayLineIsItsOwnLeverOnly() {
        let mine = UUID(), other = UUID()
        let levers = [
            DailyLever(id: other, goalTitle: "Other", projectID: nil, action: "Apply to 2 jobs", reason: "", status: .behind, urgency: 2),
            DailyLever(id: mine, goalTitle: "Interview-ready", projectID: nil, action: "3 LeetCode questions", reason: "", status: .behind, urgency: 1),
        ]
        XCTAssertEqual(CalmSurfaces.goalTodayLine(levers: levers, keyResultIDs: [mine]), "Today: 3 LeetCode questions")
        XCTAssertNil(CalmSurfaces.goalTodayLine(levers: levers, keyResultIDs: [UUID()]))
        let said = DailyLever(id: other, goalTitle: "Jobs", projectID: nil, action: "Job applications: 1 today", reason: "", status: .behind, urgency: 1)
        XCTAssertEqual(CalmSurfaces.goalTodayLine(levers: [said], keyResultIDs: [other]), "Job applications: 1 today", "Today is said once")
    }

    // MARK: Settings → Focus: target per day type

    func testTargetRowsFollowTheGoalUntilYouSetANumber() {
        let rows = CalmSurfaces.targetRows(yours: [.leave: 180], goalMinutes: 150)
        XCTAssertEqual(rows.map(\.type), [.leave, .weekend, .holiday, .sick], "A workday follows the Goals rules, not a row")
        XCTAssertEqual(rows[0].caption, "3h")
        XCTAssertEqual(rows[0].effective, 180)
        XCTAssertEqual(rows[1].caption, "Follows your goal (2h 30m)")
        XCTAssertEqual(rows[1].effective, 150)
        XCTAssertEqual(rows[3].caption, "Rest")
        XCTAssertEqual(rows[3].effective, 0)
    }

    func testTogglingAnOwnNumberStartsFromTodaysJudgement() {
        let rows = CalmSurfaces.targetRows(yours: [:], goalMinutes: 150)
        XCTAssertEqual(CalmSurfaces.toggledTarget(rows[1], ownNumber: true), 150, "Weekend starts from the goal it followed")
        XCTAssertEqual(CalmSurfaces.toggledTarget(rows[3], ownNumber: true), 30, "A sick day never stores rest by accident")
        XCTAssertNil(CalmSurfaces.toggledTarget(rows[1], ownNumber: false))
    }
}

/// Phase 5 against a real (in-memory) store: the settings binding and the reads the calm surfaces
/// make while drawing.
@MainActor
final class CalmSurfacesStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var vm: TimerViewModel!

    private static let schema = Schema([
        Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
        TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self,
        WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        BlockStartEvent.self, ActivityHour.self, DayLabel.self, AppRoleRuleRecord.self,
    ])

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        vm = nil; container = nil
        try await super.tearDown()
    }

    private func makeVM() throws -> TimerViewModel {
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let settings = AppSettings(); settings.dailyFocusGoal = 9000
        context.insert(settings)
        try context.save()
        let vm = TimerViewModel(defaults: UserDefaults(suiteName: "test.calm.\(UUID().uuidString)")!)
        vm.systemIdleSecondsProvider = { 0 }
        vm.coachExploreSizes = false
        vm.configureForEvidence(modelContext: context, settings: settings)
        return vm
    }

    /// The settings rows write through `setDayTarget` and read back through `dayTargets`.
    func testTheDayTargetRowsBindToTheViewModel() throws {
        vm = try makeVM()
        let revision = vm.dayTargetsRevision
        let weekend = try XCTUnwrap(CalmSurfaces.targetRows(yours: vm.dayTargets(), goalMinutes: 150).first { $0.type == .weekend })
        vm.setDayTarget(CalmSurfaces.toggledTarget(weekend, ownNumber: true), for: .weekend)
        XCTAssertEqual(vm.dayTargets()[.weekend], 150)
        XCTAssertGreaterThan(vm.dayTargetsRevision, revision, "Settings and Today redraw on a change")
        vm.setDayTarget(120, for: .weekend)
        let row = try XCTUnwrap(CalmSurfaces.targetRows(yours: vm.dayTargets(), goalMinutes: 150).first { $0.type == .weekend })
        XCTAssertEqual(row.caption, "2h")
        XCTAssertFalse(row.followsGoal)
        vm.setDayTarget(CalmSurfaces.toggledTarget(row, ownNumber: false), for: .weekend)
        XCTAssertNil(vm.dayTargets()[.weekend], "Switched off: back to following the goal")
    }

    /// Crash 2026-10-28 rule: every read Today, the notch, Goals and Settings → Focus make while
    /// drawing must leave observed state alone (or SwiftUI loops in layout and the app quits).
    func testCalmSurfaceReadsNeverChangeObservedState() throws {
        vm = try makeVM()
        let vm = try XCTUnwrap(self.vm)
        let today = Date()
        let reads = {
            _ = vm.dailyGoal(now: today)
            _ = vm.goalProgressSeconds(now: today)
            _ = vm.goalPacing(now: today)
            _ = vm.settledDayType(now: today.addingTimeInterval(700)) // past the 10-min cache: recomputes
            _ = vm.dayTimeline(today, now: today)
            _ = vm.dayTargets()
            _ = vm.dayTargetsRevision
            _ = vm.dailyReminder(now: today)
        }
        reads()

        final class Flag: @unchecked Sendable { var raised = false }
        let invalidated = Flag()
        withObservationTracking {
            _ = vm.state
            _ = vm.todayFocusTime
            reads()
        } onChange: {
            invalidated.raised = true
        }
        // Later redraws, past every cache window (drift rule keys 5 min, day type 10 min), so the
        // caches the tracked pass read are refreshed: a refresh must not count as a change.
        _ = vm.dailyGoal(now: today.addingTimeInterval(2_000))
        _ = vm.settledDayType(now: today.addingTimeInterval(4_000))
        _ = vm.dayLedger(days: 1, now: today.addingTimeInterval(6_000))
        _ = vm.goalPacing(now: today.addingTimeInterval(6_000))
        XCTAssertFalse(invalidated.raised, "A read made while drawing changed observed state")
    }

    /// Source contracts: the popover starts and controls a block, the quote shows on Today only.
    func testEachSurfaceHasOneJob() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/\(path)"), encoding: .utf8)
        }
        let popover = try source("Views/MenuBar/MenuBarPopoverView.swift") + source("Views/MenuBar/PopoverPlanStrip.swift")
        XCTAssertFalse(popover.contains("DailyReminderView"), "No quote in the popover")
        XCTAssertFalse(popover.contains("GoalRing"), "No ring in the idle popover")
        XCTAssertFalse(popover.contains("Verdict"), "No footer stats")
        let notch = try source("Views/Notch/NotchView.swift") + source("Views/Notch/NotchController.swift")
        XCTAssertFalse(notch.contains("dailyReminder"), "No quote in the notch")
        XCTAssertFalse(notch.contains("verdict"), "No totals line in the notch")
        let todayView = try source("Views/Companion/TodayView.swift")
        XCTAssertTrue(todayView.contains("DailyReminderView("), "The day's line lives on Today")
        XCTAssertFalse(todayView.contains("derailerTotals"), "Distractions moved to Insights")
        let goals = try source("Views/Goals/GoalsView.swift")
        XCTAssertFalse(goals.contains("DailyGoalCard("), "The daily goal moved to Settings → Focus")
        XCTAssertTrue(try source("Views/Companion/SettingsView.swift").contains("DayTargetsSettingsSection("))
    }
}
