import XCTest
@testable import FocusFlow

final class FocusAnalyticsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private var analytics: FocusAnalytics { FocusAnalytics(calendar: calendar) }

    /// 2026-10-14 is a Wednesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func block(_ day: Int, _ hour: Int, _ minute: Int = 0, minutes: Double, project: AnalyticsProjectKey = .unassigned, outcome: SessionOutcome? = nil, priority: UUID? = nil, month: Int = 10) -> FocusSample {
        FocusSample(start: date(day, hour, minute, month: month), activeSeconds: minutes * 60, project: project, priorityID: priority, outcome: outcome)
    }

    private let novel = AnalyticsProjectKey.project(id: UUID(), name: "Novel", colorName: "purple")
    private let app = AnalyticsProjectKey.project(id: UUID(), name: "Side App", colorName: "mint")

    // MARK: - Empty store

    func testEmptyStoreProducesEmptyResultsEverywhere() {
        let now = date(14, 15)
        let days = analytics.dailyTotals([], trailing: 7, endingAt: now)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { $0.seconds == 0 && $0.blocks == 0 && $0.byProject.isEmpty })

        let summary = analytics.rangeSummary(days, goal: 7200)
        XCTAssertEqual(summary.totalSeconds, 0)
        XCTAssertEqual(summary.goalMetDays, 0)
        XCTAssertNil(summary.bestDay)

        XCTAssertEqual(analytics.streak([], goal: 7200, now: now), .init(current: 0, best: 0, todayMet: false, neverMissTwice: .noHistory))
        let matrix = analytics.hourOfWeek([], now: now)
        XCTAssertTrue(matrix.isEmpty)
        XCTAssertEqual(analytics.bestWindows(matrix), [])
        XCTAssertNil(analytics.nextWindow([], after: now))
        XCTAssertEqual(analytics.weekOverWeek([], goal: 7200, now: now).thisWeekSeconds, 0)
        XCTAssertNil(analytics.weekOverWeek([], goal: 7200, now: now).deltaFraction)
        XCTAssertTrue(analytics.projectTotals([], in: analytics.weekInterval(containing: now)).isEmpty)
        XCTAssertEqual(analytics.priorityBreakdown([], priorities: [], now: now).totalSeconds, 0)
        XCTAssertEqual(analytics.outcomeMix([]).ratedCount, 0)
        XCTAssertEqual(analytics.outcomeMix([]).realWorkShare, 0)
        XCTAssertTrue(analytics.derailers([], now: now).isEmpty)
        let coach = analytics.coachEffectiveness(prompts: [], sessions: [], in: analytics.weekInterval(containing: now))
        XCTAssertFalse(coach.hasData)
        XCTAssertNil(coach.rate)
        XCTAssertEqual(coach.promptsPerDay, 0)
    }

    // MARK: - Daily totals

    func testCrossMidnightBlockIsSplitAcrossBothDays() {
        // 23:00 on the 13th for 2h of active time → 1h on each day.
        let sessions = [block(13, 23, minutes: 120, project: novel)]
        let days = analytics.dailyTotals(sessions, days: [date(13, 0), date(14, 0)])
        XCTAssertEqual(days[0].seconds, 3600, accuracy: 0.5)
        XCTAssertEqual(days[1].seconds, 3600, accuracy: 0.5)
        XCTAssertEqual(days[0].blocks, 1)
        XCTAssertEqual(days[1].blocks, 1)
        XCTAssertEqual(days[1].byProject.first?.project, novel)
    }

    func testBreaksAreIgnoredAndSplitsShareTime() {
        let split = FocusSample(
            start: date(14, 11),
            activeSeconds: 3600,
            project: novel,
            shares: [.init(project: novel, weight: 900), .init(project: app, weight: 2700)]
        )
        let rest = FocusSample(start: date(14, 12), activeSeconds: 900, isFocus: false)
        let day = analytics.dayTotal([split, rest], on: date(14, 0))
        XCTAssertEqual(day.seconds, 3600, accuracy: 0.5)
        XCTAssertEqual(day.byProject.map(\.project), [app, novel])
        XCTAssertEqual(day.byProject.first?.seconds ?? 0, 2700, accuracy: 0.5)
    }

    func testFocusSampleFromSessionExcludesPausedTime() {
        let session = FocusSession(type: .focus, duration: 3600)
        session.startedAt = date(14, 22)
        session.endedAt = date(14, 23)
        session.totalPausedSeconds = 600
        session.completed = true
        session.outcome = .shipped
        let sample = FocusSample(session)
        XCTAssertEqual(sample.activeSeconds, 3000, accuracy: 0.5)
        XCTAssertEqual(sample.outcome, .shipped)
        XCTAssertEqual(sample.project, .unassigned)
    }

    // MARK: - Goal and streaks

    func testGoalProgressReportsRemainingAndSurplus() {
        let partial = analytics.goalProgress([block(14, 11, minutes: 100)], on: date(14, 0), goal: 7200, stretch: 9000)
        XCTAssertFalse(partial.isMet)
        XCTAssertEqual(partial.remainingSeconds, 1200, accuracy: 0.5)
        XCTAssertEqual(partial.fraction, 100.0 / 120.0, accuracy: 0.001)

        let met = analytics.goalProgress([block(14, 11, minutes: 132)], on: date(14, 0), goal: 7200, stretch: 9000)
        XCTAssertTrue(met.isMet)
        XCTAssertFalse(met.isStretchMet)
        XCTAssertEqual(met.surplusSeconds, 720, accuracy: 0.5)
        XCTAssertEqual(met.fraction, 1)
    }

    func testStreakCountsBackFromYesterdayWhileTodayIsOpen() {
        let sessions = [9, 10, 11].map { block($0, 22, minutes: 125) }
            + [block(12, 22, minutes: 125), block(13, 22, minutes: 130), block(14, 11, minutes: 30)]
        let streak = analytics.streak(sessions, goal: 7200, now: date(14, 15))
        XCTAssertEqual(streak.current, 5)
        XCTAssertEqual(streak.best, 5)
        XCTAssertFalse(streak.todayMet)
        XCTAssertEqual(streak.neverMissTwice, .onTrack)
    }

    func testStreakNeverMissTwiceStates() {
        let base = [8, 9, 10, 11].map { block($0, 11, minutes: 121) }
        // Missed the 13th only.
        let missedOnce = analytics.streak(base + [block(12, 11, minutes: 121), block(13, 11, minutes: 20)], goal: 7200, now: date(14, 9))
        XCTAssertEqual(missedOnce.current, 0)
        XCTAssertEqual(missedOnce.best, 5)
        XCTAssertEqual(missedOnce.neverMissTwice, .missedYesterday)

        // Missed the 12th and 13th.
        let missedTwice = analytics.streak(base, goal: 7200, now: date(14, 9))
        XCTAssertEqual(missedTwice.neverMissTwice, .missedTwice)
        XCTAssertEqual(missedTwice.best, 4)

        // Meeting the goal today clears the warning and extends nothing before the gap.
        let recovered = analytics.streak(base + [block(14, 8, minutes: 125)], goal: 7200, now: date(14, 12))
        XCTAssertEqual(recovered.current, 1)
        XCTAssertTrue(recovered.todayMet)
        XCTAssertEqual(recovered.neverMissTwice, .onTrack)
    }

    func testRangeSummaryCountsGoalDaysAndBestDay() {
        let sessions = [block(12, 11, minutes: 130), block(13, 22, minutes: 60), block(14, 11, minutes: 150)]
        let days = analytics.dailyTotals(sessions, trailing: 7, endingAt: date(14, 18))
        let summary = analytics.rangeSummary(days, goal: 7200)
        XCTAssertEqual(summary.goalMetDays, 2)
        XCTAssertEqual(summary.dayCount, 7)
        XCTAssertEqual(summary.totalSeconds, 340 * 60, accuracy: 1)
        XCTAssertEqual(summary.dailyAverageSeconds, 340 * 60 / 7, accuracy: 1)
        XCTAssertEqual(summary.bestDay?.day, date(14, 0))
    }

    // MARK: - Hour of week and best windows

    private var habitSessions: [FocusSample] {
        // Four weeks: weekday mornings 11:00–12:00 and weekday nights 22:00–23:55.
        let weekdayStarts = [21, 22, 23, 24, 25] // Mon–Fri, 2026-09-21…
        return (0..<4).flatMap { week -> [FocusSample] in
            weekdayStarts.flatMap { weekday -> [FocusSample] in
                let start = calendar.date(byAdding: .day, value: week * 7, to: date(weekday, 0, month: 9))!
                let comps = calendar.dateComponents([.month, .day], from: start)
                return [
                    block(comps.day!, 11, minutes: 60, month: comps.month!),
                    block(comps.day!, 22, minutes: 115, month: comps.month!),
                ]
            }
        }
    }

    func testHourOfWeekMatrixAveragesPerWeekAndTracksStartRate() {
        let now = date(17, 12) // Saturday of the 4th week after 2026-09-21
        let matrix = analytics.hourOfWeek(habitSessions, weeks: 8, now: now)
        XCTAssertEqual(matrix.weeksObserved, 4)
        XCTAssertEqual(matrix.averageMinutes(weekday: 0, hour: 11), 60, accuracy: 0.01)
        XCTAssertEqual(matrix.averageMinutes(weekday: 2, hour: 23), 55, accuracy: 0.01)
        XCTAssertEqual(matrix.averageMinutes(weekday: 5, hour: 11), 0)
        XCTAssertEqual(matrix.startRate(weekday: 0, hour: 11), 1)
        XCTAssertEqual(matrix.startRate(weekday: 0, hour: 10), 0)
    }

    func testCrossMidnightBlockFillsNextWeekdayHourBucket() {
        let sessions = [block(13, 23, 30, minutes: 60)] // Tue 23:30 → Wed 00:30
        let matrix = analytics.hourOfWeek(sessions, weeks: 1, now: date(14, 12))
        XCTAssertEqual(matrix.minutes[1][23], 30, accuracy: 0.01)
        XCTAssertEqual(matrix.minutes[2][0], 30, accuracy: 0.01)
        XCTAssertEqual(matrix.startWeeks[1][23], 1)
        XCTAssertEqual(matrix.startWeeks[2][0], 0)
    }

    func testBestWindowsFindContiguousRangesIncludingTheMidnightEdge() {
        let matrix = analytics.hourOfWeek(habitSessions, weeks: 8, now: date(17, 12))
        let windows = analytics.bestWindows(matrix)
        XCTAssertEqual(windows.map(\.label), ["22–00", "11–12"])
        XCTAssertTrue(windows.allSatisfy { $0.dayScope == .weekdays })
        XCTAssertEqual(FocusAnalytics.windowsSummary(windows), "weekdays 11–12, 22–00")
    }

    func testBestWindowsMergeAcrossMidnight() {
        let sessions = (1...5).map { block($0 + 4, 23, minutes: 120) } // 23:00–01:00 every weekday
        let windows = analytics.bestWindows(analytics.hourOfWeek(sessions, weeks: 1, now: date(11, 12)))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.startHour, 23)
        XCTAssertEqual(windows.first?.hourCount, 2)
        XCTAssertEqual(windows.first?.label, "23–01")
    }

    func testNextWindowPicksUpcomingOrCurrentOccurrence() {
        let windows = analytics.bestWindows(analytics.hourOfWeek(habitSessions, weeks: 8, now: date(17, 12)))
        // Wednesday 14:00 → tonight at 22:00.
        let afternoon = analytics.nextWindow(windows, after: date(14, 14))
        XCTAssertEqual(afternoon?.start, date(14, 22))
        XCTAssertEqual(afternoon?.isNow, false)
        // Wednesday 11:30 → inside the morning window.
        let inside = analytics.nextWindow(windows, after: date(14, 11, 30))
        XCTAssertEqual(inside?.window.label, "11–12")
        XCTAssertEqual(inside?.isNow, true)
        // Saturday morning → weekday-only windows skip to Monday 11:00.
        let weekend = analytics.nextWindow(windows, after: date(17, 9))
        XCTAssertEqual(weekend?.start, date(19, 11))
    }

    // MARK: - Week over week, projects, priorities, outcomes

    func testWeekOverWeekComparesTheSameSpan() {
        let sessions = [
            block(5, 11, minutes: 120), block(6, 11, minutes: 60), block(9, 11, minutes: 300), // last week (Mon 5 … Sun 11)
            block(12, 11, minutes: 125), block(13, 22, minutes: 30),                         // this week
        ]
        let comparison = analytics.weekOverWeek(sessions, goal: 7200, now: date(13, 23, 59))
        XCTAssertEqual(comparison.thisWeekSeconds, 155 * 60, accuracy: 1)
        XCTAssertEqual(comparison.lastWeekSameSpanSeconds, 180 * 60, accuracy: 1)
        XCTAssertEqual(comparison.lastWeekSeconds, 480 * 60, accuracy: 1)
        XCTAssertEqual(comparison.deltaSeconds, -25 * 60, accuracy: 1)
        XCTAssertEqual(comparison.thisWeekGoalDays, 1)
        XCTAssertEqual(comparison.lastWeekGoalDays, 2)
    }

    func testProjectAndPriorityTotalsForThisWeek() {
        let priorityA = PrioritySample(title: "Ship v1", weekStart: date(12, 0), order: 0)
        let priorityB = PrioritySample(title: "Chapter 3", weekStart: date(12, 0), order: 1)
        let oldPriority = PrioritySample(title: "Old", weekStart: date(5, 0), order: 0)
        let sessions = [
            block(12, 11, minutes: 60, project: app, priority: priorityA.id),
            block(13, 22, minutes: 90, project: novel, priority: priorityB.id),
            block(14, 11, minutes: 30, project: app),
            block(14, 22, minutes: 15, project: app, priority: oldPriority.id),
            block(8, 11, minutes: 500, project: novel, priority: priorityB.id), // last week: ignored
        ]
        let week = analytics.weekInterval(containing: date(14, 23))
        let projects = analytics.projectTotals(sessions, in: week)
        XCTAssertEqual(projects.map(\.project), [app, novel])
        XCTAssertEqual(projects[0].seconds, 105 * 60, accuracy: 1)
        XCTAssertEqual(projects[0].sessions, 3)

        let breakdown = analytics.priorityBreakdown(sessions, priorities: [priorityB, oldPriority, priorityA], now: date(14, 23))
        XCTAssertEqual(breakdown.priorities.map(\.priority.title), ["Ship v1", "Chapter 3"])
        XCTAssertEqual(breakdown.priorities[1].seconds, 90 * 60, accuracy: 1)
        XCTAssertEqual(breakdown.untaggedSeconds, 45 * 60, accuracy: 1)
        XCTAssertEqual(breakdown.totalSeconds, 195 * 60, accuracy: 1)
    }

    func testOutcomeMixOverallAndPerProject() {
        let sessions = [
            block(12, 11, minutes: 50, project: app, outcome: .shipped),
            block(12, 22, minutes: 50, project: app, outcome: .busywork),
            block(13, 22, minutes: 50, project: app, outcome: .busywork),
            block(13, 11, minutes: 25, project: novel, outcome: .movedForward),
            block(14, 11, minutes: 25, project: novel),
        ]
        let mix = analytics.outcomeMix(sessions)
        XCTAssertEqual(mix.ratedCount, 4)
        XCTAssertEqual(mix.unratedCount, 1)
        XCTAssertEqual(mix.share(.busywork), 0.5)
        XCTAssertEqual(mix.realWorkShare, 0.5)
        XCTAssertEqual(mix.seconds[.busywork] ?? 0, 100 * 60, accuracy: 1)

        let byProject = analytics.outcomeMixByProject(sessions)
        XCTAssertEqual(byProject.map(\.project), [app, novel])
        XCTAssertEqual(byProject[0].mix.count(.busywork), 2)
        XCTAssertEqual(byProject[1].mix.unratedCount, 1)
    }

    // MARK: - Derailers

    func testDerailersCountOnlyRealDerailersOutsideFocus() {
        let thisWeek = date(13, 0)
        let lastWeek = date(6, 0)
        let usage = [
            UsageSample(day: thisWeek, appName: "YouTube", bundleIdentifier: "domain:youtube.com", duringFocusSeconds: 900, outsideFocusSeconds: 5400),
            UsageSample(day: lastWeek, appName: "YouTube", bundleIdentifier: "domain:youtube.com", outsideFocusSeconds: 3600),
            UsageSample(day: thisWeek, appName: "X", bundleIdentifier: "domain:x.com", outsideFocusSeconds: 1800),
            UsageSample(day: thisWeek, appName: "Netflix", bundleIdentifier: "com.netflix.Netflix", outsideFocusSeconds: 2400),
            UsageSample(day: lastWeek, appName: "ZEE5", bundleIdentifier: "com.zee5.app", outsideFocusSeconds: 1200),
            // Work tools and system processes never count, even with big numbers or a confirmed rule.
            UsageSample(day: thisWeek, appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", outsideFocusSeconds: 20_000),
            UsageSample(day: thisWeek, appName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", outsideFocusSeconds: 20_000),
            UsageSample(day: thisWeek, appName: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop", outsideFocusSeconds: 20_000),
            UsageSample(day: thisWeek, appName: "Arc", bundleIdentifier: "company.thebrowser.Browser", outsideFocusSeconds: 20_000),
            UsageSample(day: thisWeek, appName: "Jira", bundleIdentifier: "domain:acme.atlassian.net", outsideFocusSeconds: 20_000),
            UsageSample(day: thisWeek, appName: "loginwindow", bundleIdentifier: "com.apple.loginwindow", outsideFocusSeconds: 20_000),
            UsageSample(day: thisWeek, appName: "Hacker News", bundleIdentifier: "domain:news.ycombinator.com", outsideFocusSeconds: 900),
        ]
        let derailers = analytics.derailers(
            usage,
            now: date(14, 15),
            confirmedKeys: ["news.ycombinator.com", "com.tinyspeck.slackmacgap"]
        )
        XCTAssertEqual(derailers.map(\.name), ["YouTube", "Netflix", "X", "Hacker News", "ZEE5"])
        XCTAssertEqual(derailers[0].thisWeekSeconds, 5400)
        XCTAssertEqual(derailers[0].lastWeekSeconds, 3600)
        XCTAssertEqual(derailers.last?.thisWeekSeconds, 0)
        XCTAssertEqual(derailers.last?.lastWeekSeconds, 1200)

        let allowed = analytics.derailers(usage, now: date(14, 15), allowedKeys: ["netflix.com", "com.netflix.netflix"])
        XCTAssertFalse(allowed.contains { $0.name == "Netflix" })
    }

    func testTodayDerailersHonourMinimumThreshold() {
        let today = date(14, 0)
        let usage = [
            UsageSample(day: today, appName: "YouTube", bundleIdentifier: "domain:youtube.com", outsideFocusSeconds: 1500),
            UsageSample(day: today, appName: "Reddit", bundleIdentifier: "domain:reddit.com", outsideFocusSeconds: 300),
        ]
        let totals = analytics.derailerTotals(usage, in: analytics.dayInterval(containing: today), minimumSeconds: 600)
        XCTAssertEqual(totals.map(\.name), ["YouTube"])
    }

    // MARK: - Coach effectiveness

    func testCoachEffectivenessMeasuresStartsWithinTenMinutes() {
        let prompts = [
            PromptSample(deliveredAt: date(13, 21, 50), styleRawValue: "challenger", surfaceRawValue: "panel"),  // start 22:00 → success
            PromptSample(deliveredAt: date(13, 10, 0), styleRawValue: "gentle", surfaceRawValue: "notification"), // start 10:15 → miss
            PromptSample(deliveredAt: date(13, 15, 0), styleRawValue: "challenger", surfaceRawValue: "panel"),   // nothing → miss
            PromptSample(deliveredAt: date(13, 22, 30), styleRawValue: "challenger", surfaceRawValue: "panel"),  // during focus → ignored
            PromptSample(deliveredAt: date(14, 10, 55), surfaceRawValue: "silent"),                               // control: start 11:00
            PromptSample(deliveredAt: date(14, 9, 0)),                                                            // legacy row
        ]
        let sessions = [block(13, 22, minutes: 60), block(13, 10, 15, minutes: 25), block(14, 11, minutes: 60)]
        let interval = DateInterval(start: date(13, 0), end: date(14, 23))
        let result = analytics.coachEffectiveness(prompts: prompts, sessions: sessions, in: interval)

        XCTAssertEqual(result.prompts, 4)
        XCTAssertEqual(result.startsWithinWindow, 1)
        XCTAssertEqual(result.rate ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.days, 2)
        XCTAssertEqual(result.promptsPerDay, 2, accuracy: 0.0001)
        XCTAssertEqual(result.byStyle.map(\.label), ["Gentle", "Challenger"])
        XCTAssertEqual(result.byStyle.last?.prompts, 2)
        XCTAssertEqual(result.byStyle.last?.rate ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.bySurface.map(\.key), ["panel", "notification"])
        XCTAssertEqual(result.silentBaseline?.rate, 1)
    }

    // MARK: - Midnight-crossing blocks

    func testMidnightCrossingBlockCountsOnlyItsOverlapOnEachDay() {
        // 22:12 on the 13th for 110 minutes ends at 00:02 on the 14th.
        let late = block(13, 22, 12, minutes: 110)
        let samples = [late]

        XCTAssertEqual(analytics.dayTotal(samples, on: date(13, 12)).seconds, 108 * 60, accuracy: 0.001) // 22:12 → midnight
        XCTAssertEqual(analytics.dayTotal(samples, on: date(14, 12)).seconds, 2 * 60, accuracy: 0.001)
        XCTAssertEqual(late.overlap(with: analytics.dayInterval(containing: date(14, 12))), 120, accuracy: 0.001)
    }
}
