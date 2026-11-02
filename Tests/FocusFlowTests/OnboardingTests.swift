import XCTest
import SwiftData
import SwiftUI
@testable import FocusFlow

@MainActor
final class OnboardingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10-26
    /// A context traps once its container is gone, so the test case holds it.
    private var container: ModelContainer?

    private func makeContext() throws -> (ModelContainer, ModelContext, AppSettings) {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self,
            AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self,
            IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)
        return (container, context, settings)
    }

    // MARK: Launch

    func testLaunchShowsOnlyForAnEmptyStoreThatNeverFinished() {
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: nil, hasSessions: false), .show)
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: nil, hasSessions: true), .markDone, "Existing users are not shown the tour")
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: now, hasSessions: false), OnboardingLaunch.none)
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: now, hasSessions: true), OnboardingLaunch.none)
    }

    func testStepsRunInOrder() {
        XCTAssertEqual(OnboardingStep.allCases, [.meet, .what, .measure, .when, .plan], "The coach meets you first")
        XCTAssertEqual(OnboardingStep.meet.next, .what)
        XCTAssertNil(OnboardingStep.plan.next)
        XCTAssertNil(OnboardingStep.meet.previous)
    }

    /// `now`'s day at hh:mm in the test machine's time zone.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(byAdding: .minute, value: hour * 60 + minute, to: Calendar.current.startOfDay(for: now))!
    }

    // MARK: Draft

    func testContinueNeedsAGoalAndAWindow() {
        var draft = OnboardingDraft(now: at(15))
        XCTAssertTrue(draft.canContinue(from: .meet))
        XCTAssertFalse(draft.canContinue(from: .what))
        draft.projectName = "  "
        XCTAssertFalse(draft.canContinue(from: .what))
        draft.apply(OnboardingProjectPreset.all[0])
        XCTAssertTrue(draft.canContinue(from: .what))
        XCTAssertTrue(draft.canContinue(from: .measure), "The number and first step are optional")
        XCTAssertTrue(draft.canContinue(from: .when), "A window is preselected")
        draft.windows = []
        XCTAssertFalse(draft.canContinue(from: .when))
    }

    func testAGoalPrefillsWhatToCount() {
        var draft = OnboardingDraft()
        XCTAssertTrue(draft.tracksNumber, "Tracking the goal is the coach's job: on by default")
        draft.apply(OnboardingProjectPreset.all.first { $0.name == "Land a better job" }!)
        XCTAssertEqual(draft.area, .learning, "Your job search is your own work, not Work")
        XCTAssertEqual(draft.resultTitle, "Practice problems")
        XCTAssertEqual(draft.resultTarget, 60)
        XCTAssertTrue(draft.hasGoal)
        XCTAssertEqual(draft.resultSuggestions.map(\.title), ["Practice problems", "Mock interviews"])
        XCTAssertEqual(OnboardingDraft.inferArea(from: "Land a better job"), .learning)
    }

    func testPresetSetsKindColourIconAndHints() {
        var draft = OnboardingDraft()
        draft.apply(OnboardingProjectPreset.all.first { $0.name == "Read more books" }!)
        XCTAssertEqual(draft.area, .personal)
        XCTAssertEqual(draft.color, "green")
        XCTAssertEqual(draft.icon, "book.fill")
        XCTAssertEqual(draft.firstStepSuggestions.first, "Read 20 pages")
        XCTAssertEqual(draft.whyHint, "A wider mind, a calmer evening")
        XCTAssertFalse(OnboardingProjectPreset.all.contains { $0.area == .work }, "A #1 preset is never Work: the honest split leaves Work out of own work")
        draft.apply(OnboardingProjectPreset.all.first { $0.name == "Ship my side project" }!)
        draft.setArea(.learning)
        XCTAssertEqual(draft.icon, "hammer.fill", "A preset's own icon is kept")
    }

    func testKindFollowsATypedNameUntilYouPickOne() {
        var draft = OnboardingDraft()
        draft.projectName = "LeetCode grind"
        draft.nameChanged()
        XCTAssertEqual(draft.area, .learning)
        XCTAssertEqual(draft.icon, ProjectArea.learning.symbol)
        draft.projectName = "Client office work"
        draft.nameChanged()
        XCTAssertEqual(draft.area, .work)
        draft.projectName = "Guitar"
        draft.nameChanged()
        XCTAssertEqual(draft.area, .personal)
        draft.setArea(.learning)
        draft.projectName = "Guitar practice"
        draft.nameChanged()
        XCTAssertEqual(draft.area, .learning, "A picked kind sticks")
        XCTAssertEqual(OnboardingDraft.freshColor(avoiding: ["blue", "orange"]), "teal")
    }

    func testPrefillUsesTheRankedProjectAndSavedChoices() throws {
        let (_, context, settings) = try makeContext()
        settings.coachStyleRawValue = CoachStyle.gentle.rawValue
        settings.coachOwnWorkWindows = [CoachOwnWorkWindow(startMinute: 22 * 60, endMinute: 24 * 60)]
        let office = Project(name: "Office", color: "blue")
        let learning = Project(name: "Learning", color: "purple", icon: "book.fill")
        learning.priorityRank = 1
        learning.area = .learning
        learning.dailyTargetMinutes = 120
        learning.purpose = "Interview-ready by December"
        context.insert(office)
        context.insert(learning)

        let draft = OnboardingDraft(projects: [office, learning], settings: settings, now: at(15))
        XCTAssertEqual(draft.existingProjectID, learning.id)
        XCTAssertEqual(draft.projectName, "Learning")
        XCTAssertEqual(draft.icon, "book.fill")
        XCTAssertEqual(draft.dailyMinutes, 120)
        XCTAssertEqual(draft.why, "Interview-ready by December")
        XCTAssertEqual(draft.coachStyle, .gentle)
        XCTAssertEqual(draft.windows, settings.coachOwnWorkWindows)

        let unranked = OnboardingDraft(projects: [office, Project(name: "Other")], settings: nil)
        XCTAssertNil(unranked.existingProjectID, "With several unranked projects nothing is guessed")
    }

    // MARK: Windows

    func testWindowPresetsAvoidQuietHoursAndMidnight() {
        for preset in OnboardingWindowPreset.all {
            XCTAssertGreaterThanOrEqual(preset.window.startMinute, 7 * 60, "\(preset.title) starts inside the default quiet hours")
            XCTAssertLessThanOrEqual(preset.window.endMinute, 24 * 60)
        }
        XCTAssertEqual(OnboardingWindowPreset.suggested(now: at(22, 30)).title, "Late night", "The time you're in now")
        XCTAssertEqual(OnboardingWindowPreset.suggested(now: at(15)).title, "Evening")
        XCTAssertEqual(OnboardingDraft.label(OnboardingWindowPreset.all.last!.window), "22:00–00:00")
    }

    func testWindowsToggleAddAndCheckCapacity() {
        var draft = OnboardingDraft(now: at(15)) // Evening 20–22
        draft.projectName = "Interview prep"
        draft.dailyMinutes = 60
        XCTAssertEqual(draft.weekLine, "Every day 20:00–22:00 · 1h → 7h a week on Interview prep")
        XCTAssertFalse(draft.exceedsWindows)
        draft.dailyMinutes = 180
        XCTAssertTrue(draft.exceedsWindows, "3h a day doesn't fit a 2h window")
        draft.toggle(OnboardingWindowPreset.all[0].window) // 07–09
        XCTAssertEqual(draft.windows.map(\.startMinute), [7 * 60, 20 * 60], "Sorted")
        XCTAssertFalse(draft.exceedsWindows)
        draft.addCustom(CoachOwnWorkWindow(startMinute: 21 * 60, endMinute: 23 * 60))
        XCTAssertEqual(draft.windows.map(\.label), ["07:00–09:00", "21:00–23:00"], "An overlapping custom time replaces the preset")
        draft.toggle(OnboardingWindowPreset.all[0].window)
        XCTAssertEqual(draft.windows.count, 1)
        draft.setArea(.work)
        XCTAssertTrue(draft.weekLine.hasPrefix("Weekdays"))
    }

    func testEndingStartsInsideAWindowElsePlansTheNextOne() {
        var draft = OnboardingDraft(now: at(15))
        draft.windows = [CoachOwnWorkWindow(startMinute: 7 * 60, endMinute: 9 * 60), CoachOwnWorkWindow(startMinute: 22 * 60, endMinute: 24 * 60)]
        XCTAssertEqual(draft.ending(now: at(22, 30)), .startNow(draft.windows[1]))
        XCTAssertEqual(draft.ending(now: at(21, 55)), .startNow(draft.windows[1]), "Ten minutes before counts")
        XCTAssertEqual(draft.ending(now: at(15)), .planAt(at(22)))
        let tomorrowSeven = Calendar.current.date(byAdding: .day, value: 1, to: at(7))!
        XCTAssertEqual(draft.ending(now: at(9, 30)), .planAt(at(22)))
        draft.windows = [draft.windows[0]]
        XCTAssertEqual(draft.ending(now: at(15)), .planAt(tomorrowSeven))
        draft.windows = []
        XCTAssertEqual(draft.ending(now: at(15)), OnboardingEnding.none)

        XCTAssertEqual(OnboardingDraft.when(at(22), now: at(15)), "tonight at 22:00")
        XCTAssertEqual(OnboardingDraft.when(at(12), now: at(9)), "today at 12:00")
        XCTAssertEqual(OnboardingDraft.when(tomorrowSeven, now: at(15)), "tomorrow at 07:00")
    }

    // MARK: Copy

    func testPaceAndQuotaRoundLikeTheLevers() {
        var draft = OnboardingDraft()
        draft.resultTitle = "Practice problems"
        draft.resultTarget = 60
        draft.deadlineDays = 30
        XCTAssertEqual(draft.paceText, "2/day for 1 month")
        XCTAssertEqual(draft.dailyQuota, 2)
        draft.resultTarget = 90
        XCTAssertEqual(draft.dailyQuota, 3, "3.0 stays 3")
        draft.resultTarget = 10
        XCTAssertEqual(draft.paceText, "1 every 3 days for 1 month")
        XCTAssertEqual(draft.dailyQuota, 1)
        XCTAssertEqual(draft.resultUnit(1), "practice problem")
        XCTAssertEqual(draft.resultUnit(2), "practice problems")
        draft.resultTitle = "Classes"
        XCTAssertEqual(draft.resultUnit(1), "class")
        draft.resultTitle = "Lessons"
        XCTAssertEqual(draft.resultUnit(1), "lesson")
        draft.resultTitle = "Progress"
        XCTAssertEqual(draft.resultUnit(1), "progress")
    }

    func testStepTitleIsWhatYouTypedElseTheGoalsCount() {
        var draft = OnboardingDraft()
        XCTAssertNil(draft.stepTitle)
        draft.tracksNumber = true
        draft.apply(OnboardingResultPreset(title: "Practice problems", target: 60))
        XCTAssertEqual(draft.stepTitle, "Practice problems", "Counted: named for what you count")
        draft.resultTarget = 10
        XCTAssertEqual(draft.stepTitle, "1 practice problem")
        draft.firstStep = "  Solve 2 easy problems "
        XCTAssertEqual(draft.stepTitle, "Solve 2 easy problems")
    }

    // MARK: Commit

    func testCommitCreatesTheNumberOneProjectWindowsWhyTaskAndPlan() throws {
        let (_, context, settings) = try makeContext()
        let old = Project(name: "Office", color: "blue")
        old.priorityRank = 1
        context.insert(old)
        settings.coachMyWhyText = "Ship by December"

        var draft = OnboardingDraft(now: at(15))
        draft.apply(OnboardingProjectPreset.all[0]) // Land a better job, learning
        draft.tracksNumber = false
        draft.why = " A better role by March "
        draft.windows = [OnboardingWindowPreset.all.last!.window]
        draft.dailyMinutes = 90
        draft.firstStep = "Solve 2 easy problems"
        draft.coachStyle = .data

        let top = try XCTUnwrap(draft.commit(projects: [old], goals: [], settings: settings, in: context, now: at(15), planStart: at(22), blockMinutes: 25))
        XCTAssertEqual(top.name, "Land a better job", "The goal names the #1")
        XCTAssertEqual(top.color, "blue", "A preset keeps its colour")
        XCTAssertEqual(top.priorityRank, 1)
        XCTAssertEqual(top.area, .learning)
        XCTAssertEqual(top.purpose, "A better role by March")
        XCTAssertEqual(top.dailyTargetMinutes, 90)
        XCTAssertEqual(top.targetWeekdaysOnly, false)
        XCTAssertEqual(old.priorityRank, 2, "The old #1 moves down")

        XCTAssertEqual(settings.coachOwnWorkWindows.map(\.label), ["22:00–24:00"])
        XCTAssertEqual(settings.coachMyWhyLines, ["Ship by December", "A better role by March"])
        XCTAssertEqual(settings.coachStyle, .data)
        XCTAssertFalse(settings.coachPauseScreenEnabled, "The pause screen is Challenger's")
        XCTAssertEqual(settings.onboardingCompletedAt, at(15))
        XCTAssertEqual(settings.dailyFocusGoal, 90 * 60, "Own work sets the daily goal")
        XCTAssertGreaterThanOrEqual(settings.dailyStretchGoal, settings.dailyFocusGoal)

        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyTask>()).first)
        XCTAssertEqual(task.title, "Solve 2 easy problems")
        XCTAssertEqual(task.projectID, top.id)
        XCTAssertNil(task.keyResultID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectGoal>()), 0, "No number, no goal")

        let plan = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedBlock>()).first)
        XCTAssertEqual(plan.startAt, at(22))
        XCTAssertEqual(plan.minutes, 25)
        XCTAssertEqual(plan.projectID, top.id)
        XCTAssertEqual(plan.status, .planned)

        // Running it again changes nothing twice.
        draft.existingProjectID = top.id
        draft.commit(projects: [old, top], goals: [], settings: settings, in: context, now: at(15), planStart: at(22))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyTask>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedBlock>()), 1)
        XCTAssertEqual(settings.coachMyWhyLines.count, 2)
    }

    func testCommitWithANumberLinksTheFirstTaskToTheGoal() throws {
        let (_, context, settings) = try makeContext()
        var draft = OnboardingDraft(now: at(15))
        draft.projectName = "Guitar"
        draft.nameChanged()
        draft.tracksNumber = true
        draft.apply(OnboardingResultPreset(title: "Practice problems", target: 60))

        let top = try XCTUnwrap(draft.commit(projects: [Project(name: "Other", color: "purple")], goals: [], settings: settings, in: context, now: at(15)))
        XCTAssertEqual(top.color, "blue", "A typed name gets the first colour no other project uses")
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<ProjectGoal>()).first)
        XCTAssertEqual(goal.projectID, top.id)
        XCTAssertTrue(goal.isBossFight)
        XCTAssertTrue(goal.title.hasPrefix("60 practice problems by "))
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: goal.startDate, to: goal.deadline).day, 30)
        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyTask>()).first)
        XCTAssertEqual(task.title, "Practice problems", "Named for what you count; the counter shows 0 of 2")
        XCTAssertTrue(task.isCounted)
        XCTAssertEqual(task.keyResultID, goal.sortedKeyResults.first?.id)
        XCTAssertEqual(task.amount, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedBlock>()), 0, "No plan when starting now")
    }

    func testCommitOnAnExistingProjectKeepsItAndRespectsAnExistingBossFight() throws {
        let (_, context, settings) = try makeContext()
        let office = Project(name: "Office", color: "blue")
        let learning = Project(name: "Learning", color: "purple")
        context.insert(office)
        context.insert(learning)
        let boss = ProjectGoal(title: "Interview-ready", projectID: learning.id, deadline: now.addingTimeInterval(20 * 86_400), isBossFight: true)
        context.insert(boss)
        settings.dailyFocusGoal = 7200

        var draft = OnboardingDraft()
        draft.select(office)
        draft.setArea(.work)
        draft.dailyMinutes = 180
        draft.tracksNumber = true
        draft.apply(OnboardingResultPreset(title: "Docs written", target: 4))

        let top = draft.commit(projects: [office, learning], goals: [boss], settings: settings, in: context, now: now)
        XCTAssertEqual(top?.id, office.id)
        XCTAssertEqual(top?.color, "blue", "An existing project keeps its colour")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 2, "No new project")
        XCTAssertEqual(office.priorityRank, 1)
        XCTAssertEqual(office.targetWeekdaysOnly, true, "Work targets are weekdays only")
        XCTAssertEqual(settings.dailyFocusGoal, 7200, "Work doesn't change the own-work goal")
        let added = try context.fetch(FetchDescriptor<ProjectGoal>()).first { $0.projectID == office.id }
        XCTAssertEqual(added?.isBossFight, false, "Only one boss fight")
    }

    func testCommitWithoutAProjectOnlySavesChoices() throws {
        let (_, context, settings) = try makeContext()
        var draft = OnboardingDraft(now: at(15))
        draft.coachStyle = .gentle
        XCTAssertNil(draft.commit(projects: [], goals: [], settings: settings, in: context, now: now, planStart: at(20)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedBlock>()), 0, "No #1, nothing to plan")
        XCTAssertEqual(settings.coachStyle, .gentle)
        XCTAssertEqual(settings.coachOwnWorkWindows.count, 1)
        XCTAssertEqual(settings.onboardingCompletedAt, now)

        draft.projectName = "Writing"
        draft.resultTitle = "Posts"
        draft.tracksNumber = false
        draft.commit(projects: [], goals: [], settings: settings, in: context, now: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectGoal>()), 0, "Not tracking a number writes no goal")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyTask>()), 0, "No first step, no task")
    }

    func testTheTourNeverShowsATimerFirst() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/Onboarding/OnboardingView.swift"), encoding: .utf8)
        for gone in ["Start 5 minutes", "Set me up · 1 min", "OnboardingConfetti", "OnboardingHeroRing"] {
            XCTAssertFalse(view.contains(gone), "\(gone) is back")
        }
    }

    /// Look (design §3.4): premium, not a template. No glow wallpaper, no purple, no rounded
    /// headings; colour comes from the project; motion respects Reduce Motion.
    func testTheTourHasNoTemplateTells() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources/FocusFlow/Views/Onboarding")
        let view = try String(contentsOf: dir.appendingPathComponent("OnboardingView.swift"), encoding: .utf8)
        let parts = try String(contentsOf: dir.appendingPathComponent("OnboardingComponents.swift"), encoding: .utf8)
        for source in [view, parts] {
            for tell in ["RadialGradient", "OnboardingBackdrop", "OnboardingConfetti", ".purple", "\"purple\""] {
                XCTAssertFalse(source.contains(tell), "Template tell \(tell) is back")
            }
        }
        XCTAssertFalse(view.contains("design: .rounded)\n                    .tracking"), "Headings are SF Pro, not rounded")
        XCTAssertTrue(view.contains("accessibilityReduceMotion"))
        XCTAssertFalse(OnboardingProjectPreset.all.contains { $0.color == "purple" })
        XCTAssertFalse(OnboardingDraft.colors.contains("purple"))
    }

    func testSettingsOffersTheTourAgain() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/Companion/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(settings.contains("Button(\"Show Tour\") { timerVM.openOnboarding?() }"))
        let app = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/FocusFlowApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("OnboardingController(timerVM: timerVM, modelContainer: modelContext.container)"))
        XCTAssertTrue(app.contains("showOnboardingIfNeeded()"))
    }

    // MARK: Captures (layout only; glass renders wrong off-screen)

    func testCaptureOnboardingSteps() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_CAPTURE_OUTPUT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set FOCUSFLOW_CAPTURE_OUTPUT_DIR to capture")
        }
        let output = URL(fileURLWithPath: dir).appendingPathComponent("onboarding", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let (container, context, settings) = try makeContext()
        let existing = Project(name: "Office", color: "blue", icon: "briefcase.fill")
        context.insert(existing)
        try context.save()
        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)

        let captureNow = at(15)
        var filled = OnboardingDraft(now: captureNow)
        filled.apply(OnboardingProjectPreset.all[0])
        filled.why = "A better role by March"
        filled.windows = [OnboardingWindowPreset.all.last!.window]
        filled.firstStep = "Solve 2 easy problems"
        var tracked = filled
        tracked.tracksNumber = true
        tracked.apply(OnboardingResultPreset(title: "Practice problems", target: 60))

        for dark in [false, true] {
            for step in OnboardingStep.allCases {
                let draft = step == .what && !dark ? OnboardingDraft(now: captureNow) : (step == .measure && dark ? tracked : filled)
                let view = OnboardingView(step: step, draft: draft, now: captureNow)
                    .environment(vm)
                    .modelContainer(container)
                    .environment(\.modelContext, context)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(origin: .zero, size: OnboardingView.size)
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.appearance = appearance
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = appearance
                window.contentView = host
                window.displayIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                host.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
                let name = "\(step.rawValue + 1)_\(String(describing: step))_\(dark ? "dark" : "light").png"
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
                window.close()
            }
        }
    }
}
