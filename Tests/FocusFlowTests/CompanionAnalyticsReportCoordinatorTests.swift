import XCTest
@testable import FocusFlow

@MainActor
final class CompanionAnalyticsReportCoordinatorTests: XCTestCase {
    func testScheduleRefreshBuildsImmediatelyForFirstInput() {
        var invocationCount = 0
        let now = Self.referenceDate
        let coordinator = CompanionAnalyticsReportCoordinator(debounceInterval: 0.2, initialNow: now)
        let entry = makeEntry(appName: "YouTube", bundleIdentifier: "domain:youtube.com")

        coordinator.scheduleRefresh(
            entries: [entry],
            domainTrackingEnabled: true,
            now: now
        ) { entries, _, _ in
            invocationCount += 1
            return Self.report(label: entries.first?.appName ?? "Empty")
        }

        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(coordinator.report.today.rows.first?.label, "YouTube")
    }

    func testScheduleRefreshDebouncesRapidUpdatesAndPublishesLatestInput() async {
        var invocationCount = 0
        let now = Self.referenceDate
        let coordinator = CompanionAnalyticsReportCoordinator(debounceInterval: 0.05, initialNow: now)

        coordinator.scheduleRefresh(
            entries: [makeEntry(appName: "YouTube", bundleIdentifier: "domain:youtube.com")],
            domainTrackingEnabled: true,
            now: now
        ) { entries, _, _ in
            invocationCount += 1
            return Self.report(label: entries.first?.appName ?? "Empty")
        }

        coordinator.scheduleRefresh(
            entries: [makeEntry(appName: "Reddit", bundleIdentifier: "domain:reddit.com")],
            domainTrackingEnabled: true,
            now: now
        ) { entries, _, _ in
            invocationCount += 1
            return Self.report(label: entries.first?.appName ?? "Empty")
        }

        coordinator.scheduleRefresh(
            entries: [makeEntry(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")],
            domainTrackingEnabled: true,
            now: now
        ) { entries, _, _ in
            invocationCount += 1
            return Self.report(label: entries.first?.appName ?? "Empty")
        }

        XCTAssertEqual(invocationCount, 1, "Debounced updates should not recompute immediately.")
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(invocationCount, 2, "Rapid updates should coalesce into one trailing recompute.")
        XCTAssertEqual(coordinator.report.today.rows.first?.label, "Slack")
    }

    func testScheduleRefreshMatchesCompanionAnalyticsBuilderOutput() async {
        let now = Self.referenceDate
        let coordinator = CompanionAnalyticsReportCoordinator(debounceInterval: 0.01, initialNow: now)
        let entries = [
            makeEntry(appName: "YouTube", bundleIdentifier: "domain:youtube.com", duringFocusSeconds: 500, outsideFocusSeconds: 100),
            makeEntry(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", duringFocusSeconds: 0, outsideFocusSeconds: 300)
        ]

        coordinator.scheduleRefresh(
            entries: entries,
            domainTrackingEnabled: true,
            now: now
        ) { entries, domainTrackingEnabled, now in
            CompanionAnalyticsBuilder().build(
                entries: entries,
                domainTrackingEnabled: domainTrackingEnabled,
                now: now
            )
        }

        let expected = CompanionAnalyticsBuilder().build(
            entries: entries,
            domainTrackingEnabled: true,
            now: now
        )
        XCTAssertEqual(coordinator.report, expected)
    }

    private func makeEntry(
        appName: String,
        bundleIdentifier: String,
        duringFocusSeconds: Int = 60,
        outsideFocusSeconds: Int = 0
    ) -> AppUsageEntry {
        AppUsageEntry(
            date: Self.referenceDate,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            duringFocusSeconds: duringFocusSeconds,
            outsideFocusSeconds: outsideFocusSeconds
        )
    }

    private static func report(label: String) -> CompanionAnalyticsReport {
        let row = CompanionAnalyticsRow(
            id: label,
            label: label,
            bundleIdentifier: label,
            kind: .app,
            category: .neutral,
            duringFocusSeconds: 60,
            outsideFocusSeconds: 0
        )
        let snapshot = CompanionAnalyticsWindowSnapshot(
            window: .today,
            rows: [row],
            domainRows: [],
            domainEmptyState: nil
        )
        return CompanionAnalyticsReport(
            today: snapshot,
            trailing7Days: snapshot,
            trailing30Days: snapshot
        )
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
}
