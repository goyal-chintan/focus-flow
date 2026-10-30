import XCTest
import SwiftData
@testable import FocusFlow

/// Priorities, goals and the honest breakdown (docs/plans/2026-10-28-priorities-goals-design.md).
final class GoalTrackingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    // MARK: Pacing

    func testThirtyDayGoalPacing() {
        // 60 LeetCode in 30 days. On day 10 you should have 20.
        let deadline = day(30)
        let behind = GoalPacing.pace(target: 60, done: 8, start: start, deadline: deadline, now: day(10))
        XCTAssertEqual(behind.expected, 20, accuracy: 1e-9)
        XCTAssertEqual(behind.status, .behind)
        XCTAssertEqual(behind.neededPerDay!, 52.0 / 20, accuracy: 1e-9)
        XCTAssertEqual(behind.delta, -12, accuracy: 1e-9)
        // At 0.8/day the 52 left take 65 more days: far past the deadline.
        XCTAssertGreaterThan(behind.projectedFinish!, deadline)

        XCTAssertEqual(GoalPacing.pace(target: 60, done: 19, start: start, deadline: deadline, now: day(10)).status, .onTrack)
        XCTAssertEqual(GoalPacing.pace(target: 60, done: 25, start: start, deadline: deadline, now: day(10)).status, .ahead)
        XCTAssertEqual(GoalPacing.pace(target: 60, done: 60, start: start, deadline: deadline, now: day(10)).status, .done)
        XCTAssertEqual(GoalPacing.pace(target: 60, done: 40, start: start, deadline: deadline, now: day(31)).status, .overdue)
        XCTAssertEqual(GoalPacing.pace(target: 60, done: 0, start: start, deadline: deadline, now: day(-1)).status, .notStarted)
        XCTAssertNil(GoalPacing.pace(target: 60, done: 40, start: start, deadline: deadline, now: day(31)).neededPerDay)
    }

    func testGoalSummaryAveragesKeyResultsAgainstTime() {
        let summary = GoalPacing.summary(
            keyResults: [(60, 30), (10, 5), (1, 0)], // 50%, 50%, 0% → 33%
            start: start, deadline: day(30), now: day(15) // 50% of the time
        )
        XCTAssertEqual(summary.fraction, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(summary.expectedFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(summary.status, .behind)
        XCTAssertEqual(summary.deadlineLabel, "15 days left")
        XCTAssertEqual(GoalPacing.summary(keyResults: [(1, 1)], start: start, deadline: day(30), now: day(3)).status, .done)
    }

    func testCumulativeSeriesForThePaceChart() {
        let points = GoalPacing.cumulative([(day(2), 3), (day(1), 2), (day(3), -1)], start: start)
        XCTAssertEqual(points.map(\.done), [0, 2, 5, 4])
    }

    // MARK: Honest breakdown

    private func info(_ id: String, rank: Int?, area: ProjectArea, targetHours: Double?) -> PriorityAllocation.ProjectInfo {
        .init(id: id, name: id, colorName: nil, rank: rank, area: area, targetSeconds: targetHours.map { $0 * 3600 })
    }

    func testTenHoursTrackedButOneOnTheTopPriority() {
        let allocation = PriorityAllocation.compute(
            projects: [
                info("Office", rank: 2, area: .work, targetHours: 3),
                info("Learning", rank: 1, area: .learning, targetHours: 4),
                info("Side", rank: nil, area: .personal, targetHours: nil),
            ],
            seconds: ["Office": 8 * 3600, "Learning": 3600, "Side": 1800, "label:misc": 1800]
        )
        XCTAssertEqual(allocation.rows.map(\.id), ["Learning", "Office", "Side", "unassigned"], "Ranked first, unassigned last")
        XCTAssertEqual(allocation.totalSeconds, 10 * 3600)
        XCTAssertEqual(allocation.top?.id, "Learning")
        XCTAssertEqual(allocation.ownWorkShare, 0.15, accuracy: 1e-9)
        XCTAssertEqual(allocation.rows.first!.targetFraction!, 0.25, accuracy: 1e-9)
        let verdict = allocation.verdict { "\(Int($0 / 60))m" }
        XCTAssertEqual(verdict, "600m tracked · 60m on Learning, your #1 (target 240m) · 15% your own work")
    }

    func testDriftReportSaidVersusDid() {
        let projects = [
            info("Learning", rank: 1, area: .learning, targetHours: 4),
            info("Office", rank: 2, area: .work, targetHours: 3),
        ]
        let perDay = (0..<7).map { n in
            (day: day(Double(n)), allocation: PriorityAllocation.compute(projects: projects, seconds: ["Learning": 3600, "Office": 5 * 3600]))
        }
        let report = DriftReport.compute(perDay: perDay)
        XCTAssertEqual(report.lines.map(\.id), ["Learning", "Office"])
        XCTAssertEqual(report.lines[0].share!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(report.biggestGap?.id, "Learning")
        XCTAssertEqual(report.ownWorkShare, 1.0 / 6, accuracy: 1e-9)
        let findings = report.findings { "\(Int($0 / 3600))h" }
        XCTAssertEqual(findings.first, "Your #1, Learning, got 1h a day: 25% of the 4h you planned.")
        XCTAssertTrue(findings.contains { $0.hasPrefix("Office took 167%") })
        XCTAssertTrue(findings.contains("17% of your tracked time was your own work."))
    }

    // MARK: Levers

    func testLeversComeFromTheKeyResultsFurthestBehind() {
        func input(_ title: String, unit: String?, target: Double, done: Double, doneToday: Double = 0, boost: Double = 0) -> DailyLevers.KeyResultInput {
            .init(id: UUID(), title: title, unit: unit, target: target, done: done, doneToday: doneToday,
                  goalTitle: "Apply by Nov 28", projectID: nil, start: start, deadline: day(30), priorityBoost: boost)
        }
        let levers = DailyLevers.levers([
            input("LeetCode", unit: "questions", target: 60, done: 8),
            input("SQL", unit: "questions", target: 10, done: 4),
            input("Apply for jobs", unit: nil, target: 1, done: 0),
            input("Referral asks", unit: nil, target: 3, done: 3),
        ], now: day(10))
        XCTAssertEqual(levers.first?.action, "3 LeetCode questions", "52 left over 20 days → 2.6 → 3 today")
        XCTAssertEqual(levers.first?.status, .behind)
        XCTAssertTrue(levers.first?.reason.hasPrefix("need 2.6/day") == true)
        XCTAssertEqual(PaceFormat.rate(0.3), "1 every 3 days")
        XCTAssertEqual(PaceFormat.rate(2), "2/day")
        XCTAssertEqual(DailyLevers.unit("questions", count: 1), "question")
        XCTAssertEqual(DailyLevers.unit("questions", count: 3), "questions")
        XCTAssertEqual(DailyLevers.unit("class", count: 1), "class")
        XCTAssertFalse(levers.contains { $0.action.contains("Referral") }, "Done results are not levers")
        XCTAssertFalse(levers.contains { $0.action.contains("Apply for jobs") }, "A one-off step (target 1) is a task, never a lever")
        // Today's quota already met: no lever.
        XCTAssertTrue(DailyLevers.levers([input("LeetCode", unit: "questions", target: 60, done: 20, doneToday: 3)], now: day(10)).isEmpty)
        XCTAssertTrue(DailyLevers.levers([input("Apply for jobs", unit: nil, target: 1, done: 0)], now: day(25)).isEmpty, "Not even late")
        // Own work first: with the same pace, the boosted (★ #1 / own work) result leads.
        let ranked = DailyLevers.levers([
            input("Office tickets", unit: nil, target: 20, done: 4),
            input("LeetCode", unit: nil, target: 20, done: 4, boost: 10),
        ], now: day(10))
        XCTAssertEqual(ranked.first?.action.hasPrefix("LeetCode"), true)
    }

    // MARK: SwiftData

    @MainActor
    func testGoalModelsRoundTripAndProgressIsTheSumOfEntries() throws {
        let schema = Schema([Project.self, FocusSession.self, TimeSplit.self, BlockProfile.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let project = Project(name: "Learning")
        project.priorityRank = 1
        project.area = .learning
        project.dailyTargetMinutes = 240
        project.targetWeekdaysOnly = true
        context.insert(project)
        let goal = ProjectGoal(title: "Apply by Nov 28", projectID: project.id, startDate: start, deadline: day(30), isBossFight: true)
        context.insert(goal)
        let leet = GoalKeyResult(title: "LeetCode", kind: .count, target: 60, unit: "questions", order: 0)
        let apply = GoalKeyResult(title: "Apply", kind: .checkbox, target: 99, order: 1)
        goal.keyResults = [leet, apply]
        leet.entries = [GoalProgressEntry(amount: 2, at: day(1)), GoalProgressEntry(amount: 3, at: day(2)), GoalProgressEntry(amount: -1, at: day(2))]
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<ProjectGoal>()).first)
        XCTAssertEqual(fetched.sortedKeyResults.map(\.title), ["LeetCode", "Apply"])
        XCTAssertEqual(fetched.sortedKeyResults[0].done, 4)
        XCTAssertEqual(fetched.sortedKeyResults[1].target, 1, "A checkbox's target is 1")
        XCTAssertEqual(project.area, .learning)
        let saturday = Calendar.current.nextDate(after: start, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)!
        XCTAssertNil(project.dailyTarget(on: saturday), "Weekdays only")
        let summary = GoalDataBuilder.summary(fetched, now: day(10))
        XCTAssertEqual(summary.keyResults.first?.done, 4)
        fetched.status = .done
        XCTAssertNotNil(fetched.completedAt)
        context.delete(fetched)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<GoalProgressEntry>()).isEmpty, "Cascade deletes key results and entries")
    }

    /// Screen audit: once a project is marked Work, every companion goal mark uses own work only.
    @MainActor
    func testCompanionSnapshotCountsOwnWorkTowardTheGoal() throws {
        let schema = Schema([Project.self, FocusSession.self, TimeSplit.self, BlockProfile.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let learning = Project(name: "Learning")
        learning.area = .learning
        let office = Project(name: "Office")
        office.area = .work
        [learning, office].forEach { context.insert($0) }
        let now = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        func block(_ project: Project, hour: Int, minutes: Int) -> FocusSession {
            let session = FocusSession(type: .focus, duration: TimeInterval(minutes * 60), project: project)
            session.startedAt = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
            session.endedAt = session.startedAt.addingTimeInterval(TimeInterval(minutes * 60))
            session.completed = true
            context.insert(session)
            return session
        }
        let sessions = [block(office, hour: 9, minutes: 180), block(learning, hour: 14, minutes: 30)]
        try context.save()

        let snapshot = CompanionSnapshot(sessions: sessions, settings: nil, projects: [learning, office], now: now)
        XCTAssertTrue(snapshot.ownWorkOnly)
        let progress = snapshot.analytics.goalProgress(snapshot.goalSamples, on: now, goal: snapshot.goal, stretch: snapshot.stretch)
        XCTAssertEqual(progress.doneSeconds, 30 * 60, accuracy: 1, "3h of office must not count toward the personal goal")
        XCTAssertFalse(progress.isMet)
        XCTAssertEqual(snapshot.analytics.dayTotal(snapshot.samples, on: now).seconds, 210 * 60, accuracy: 1, "The honest total keeps everything")
        XCTAssertEqual(snapshot.workKeys, [GoalDataBuilder.projectKey(office)])

        let unconfigured = CompanionSnapshot(sessions: sessions, settings: nil, projects: [learning], now: now)
        XCTAssertFalse(unconfigured.ownWorkOnly, "Without a Work project every block counts")
        XCTAssertEqual(unconfigured.goalSamples.count, 2)
    }
}

/// Goal-aware coach copy.
final class GoalAwareCopyTests: XCTestCase {
    private func compose(_ style: CoachStyle, trigger: CoachTrigger = .startNudge, goal: CoachGoalFact?, lever: String? = "3 LeetCode questions") -> CoachComposedMessage {
        var facts = CoachFacts()
        facts.goal = goal
        facts.lever = lever
        facts.goalMinutes = 120
        return CoachMessageComposer.compose(CoachComposerInput(style: style, trigger: trigger, facts: facts, target: CoachStartTarget(minutes: 15, name: "Learning")))
    }

    func testNudgesNameTheRealStakes() {
        let behind = CoachGoalFact(goalTitle: "Interview-ready by 28 Nov", resultTitle: "LeetCode", done: 14, target: 60, behind: 11, daysLeft: 18)
        let challenger = compose(.challenger, goal: behind)
        XCTAssertEqual(challenger.hook, "18 days left. LeetCode is 11 behind.")
        XCTAssertEqual(challenger.detail, .line("Today's lever: 3 LeetCode questions."))
        XCTAssertEqual(compose(.data, goal: behind).hook, "LeetCode: 14 of 60 · 11 behind pace · 18d left.")
        XCTAssertEqual(compose(.gentle, goal: behind).hook, "Today's step: 3 LeetCode questions?")
        var onPace = behind
        onPace.behind = 0
        XCTAssertNotEqual(compose(.challenger, goal: onPace).hook, challenger.hook, "On pace: no alarm")
    }

    func testRescueShowsWhatTheDriftCosts() {
        let behind = CoachGoalFact(goalTitle: "Apply", resultTitle: "LeetCode", done: 14, target: 60, behind: 11, daysLeft: 18)
        let rescue = CoachRescueContext(level: .lost, signal: nil, spanLabel: "today", ask: CoachRescueAsk(kind: .normal, minutes: 15, title: "Start 15m", target: nil), priorityName: "Learning")
        let message = compose(.challenger, trigger: .rescue(rescue), goal: behind)
        XCTAssertEqual(message.detail, .fact("LeetCode is 11 behind with 18 days left."))
    }
}
