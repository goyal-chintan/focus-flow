import XCTest
@testable import FocusFlow

final class CompanionAnalyticsBuilderTests: XCTestCase {
    func testBuildCreatesTodaySevenDayAndThirtyDaySnapshots() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)

        let report = builder.build(
            entries: [
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "domain:youtube.com",
                    appName: "YouTube",
                    duringFocusSeconds: 600,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 6,
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    appName: "Slack",
                    duringFocusSeconds: 0,
                    outsideFocusSeconds: 900,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 29,
                    bundleIdentifier: "com.anthropic.claudefordesktop",
                    appName: "Claude",
                    duringFocusSeconds: 0,
                    outsideFocusSeconds: 300,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 30,
                    bundleIdentifier: "domain:reddit.com",
                    appName: "Reddit",
                    duringFocusSeconds: 120,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                )
            ],
            domainTrackingEnabled: true,
            now: now
        )

        XCTAssertEqual(report.today.rows.map(\.label), ["YouTube"])
        XCTAssertEqual(report.trailing7Days.rows.map(\.label), ["Slack", "YouTube"])
        XCTAssertEqual(report.trailing30Days.rows.map(\.label), ["Slack", "YouTube", "Claude"])
    }

    func testBuildSuppressesGenericBrowserRowsWhenValidDomainRowsExistInWindow() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)

        let report = builder.build(
            entries: [
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "com.apple.Safari",
                    appName: "Safari",
                    duringFocusSeconds: 1200,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "domain:youtube.com",
                    appName: "YouTube",
                    duringFocusSeconds: 1200,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    appName: "Slack",
                    duringFocusSeconds: 0,
                    outsideFocusSeconds: 600,
                    relativeTo: now,
                    calendar: calendar
                )
            ],
            domainTrackingEnabled: true,
            now: now
        )

        XCTAssertEqual(report.today.rows.map(\.bundleIdentifier), ["domain:youtube.com", "com.tinyspeck.slackmacgap"])
        XCTAssertEqual(report.today.domainRows.map(\.bundleIdentifier), ["domain:youtube.com"])
        XCTAssertNil(report.today.domainEmptyState)
    }

    func testBuildKeepsResidualBrowserTimeWhenOnlyPartOfBrowserUsageResolvesToDomains() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)

        let report = builder.build(
            entries: [
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "com.apple.Safari",
                    appName: "Safari",
                    duringFocusSeconds: 1200,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "domain:youtube.com",
                    appName: "YouTube",
                    duringFocusSeconds: 900,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    appName: "Slack",
                    duringFocusSeconds: 0,
                    outsideFocusSeconds: 600,
                    relativeTo: now,
                    calendar: calendar
                )
            ],
            domainTrackingEnabled: true,
            now: now
        )

        XCTAssertEqual(
            report.today.rows.map(\.bundleIdentifier),
            ["domain:youtube.com", "com.tinyspeck.slackmacgap", "com.apple.safari"]
        )
        XCTAssertEqual(
            report.today.rows.last?.duringFocusSeconds,
            300,
            "Residual Safari time should remain visible when only part of browser usage resolved to domains."
        )
    }

    func testBuildFiltersMalformedDomainRowsWithoutSuppressingGenericBrowsers() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)

        let report = builder.build(
            entries: [
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "com.apple.Safari",
                    appName: "Safari",
                    duringFocusSeconds: 500,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "domain:company.thebrowser.browser",
                    appName: "Arc",
                    duringFocusSeconds: 500,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                )
            ],
            domainTrackingEnabled: true,
            now: now
        )

        XCTAssertEqual(report.today.rows.map(\.bundleIdentifier), ["com.apple.safari"])
        XCTAssertTrue(report.today.domainRows.isEmpty)
        XCTAssertEqual(report.today.domainEmptyState, .noValidDomainsYet)
    }

    func testBuildReportsTrackingDisabledWhenDomainTrackingIsOff() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)

        let report = builder.build(
            entries: [],
            domainTrackingEnabled: false,
            now: now
        )

        XCTAssertEqual(report.today.domainEmptyState, .trackingDisabled)
        XCTAssertEqual(report.trailing7Days.domainEmptyState, .trackingDisabled)
        XCTAssertEqual(report.trailing30Days.domainEmptyState, .trackingDisabled)
    }

    func testBuildReportsNoValidDomainEmptyStateWhenNoValidDomainsExist() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)

        let report = builder.build(entries: [], domainTrackingEnabled: true, now: now)

        XCTAssertEqual(report.today.domainEmptyState, .noValidDomainsYet)
    }

    func testTodaySnapshotExcludesTomorrowStartBoundaryEntries() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!

        let report = builder.build(
            entries: [
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "domain:youtube.com",
                    appName: "YouTube",
                    duringFocusSeconds: 600,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                AppUsageEntry(
                    date: tomorrowStart,
                    appName: "Reddit",
                    bundleIdentifier: "domain:reddit.com",
                    duringFocusSeconds: 480,
                    outsideFocusSeconds: 0
                )
            ],
            domainTrackingEnabled: true,
            now: now
        )

        XCTAssertEqual(report.today.rows.map(\.bundleIdentifier), ["domain:youtube.com"])
        XCTAssertFalse(report.today.rows.contains { $0.bundleIdentifier == "domain:reddit.com" })
    }

    func testBuildUsesBundleIdentifierAsTieBreakerForEqualTimeEqualLabelRows() {
        let calendar = Self.utcCalendar
        let now = Self.date(year: 2026, month: 2, day: 20, hour: 15, minute: 0)
        let builder = CompanionAnalyticsBuilder(calendar: calendar)

        let report = builder.build(
            entries: [
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "domain:x.com",
                    appName: "X",
                    duringFocusSeconds: 600,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                ),
                makeEntry(
                    dayOffset: 0,
                    bundleIdentifier: "domain:twitter.com",
                    appName: "X",
                    duringFocusSeconds: 600,
                    outsideFocusSeconds: 0,
                    relativeTo: now,
                    calendar: calendar
                )
            ],
            domainTrackingEnabled: true,
            now: now
        )

        XCTAssertEqual(
            report.today.domainRows.map(\.bundleIdentifier),
            ["domain:twitter.com", "domain:x.com"]
        )
    }

    private func makeEntry(
        dayOffset: Int,
        bundleIdentifier: String,
        appName: String,
        duringFocusSeconds: Int,
        outsideFocusSeconds: Int,
        relativeTo now: Date,
        calendar: Calendar
    ) -> AppUsageEntry {
        let dayStart = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: .day, value: -dayOffset, to: dayStart) ?? dayStart
        return AppUsageEntry(
            date: date,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            duringFocusSeconds: duringFocusSeconds,
            outsideFocusSeconds: outsideFocusSeconds
        )
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
