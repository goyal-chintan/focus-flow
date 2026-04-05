import XCTest
@testable import FocusFlow

final class InsightsAppUsagePolicyTests: XCTestCase {
    private let builder = FocusCoachInsightsBuilder()

    func testFilterEntriesRemovesPersistedDomainRowsWhenRawCaptureDisabled() {
        let visibleEntries = InsightsAppUsagePolicy.visibleEntries(
            from: [
                AppUsageEntry(
                    date: Date(),
                    appName: "YouTube",
                    bundleIdentifier: "domain:youtube.com",
                    duringFocusSeconds: 12 * 60,
                    outsideFocusSeconds: 0
                ),
                AppUsageEntry(
                    date: Date(),
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    duringFocusSeconds: 8 * 60,
                    outsideFocusSeconds: 0
                )
            ],
            collectRawDomains: false
        )

        XCTAssertEqual(visibleEntries.map(\AppUsageEntry.bundleIdentifier), ["com.apple.Safari"])
    }

    func testFilterEntriesKeepsPersistedDomainRowsWhenRawCaptureEnabled() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 12 * 60,
                outsideFocusSeconds: 0
            ),
            AppUsageEntry(
                date: Date(),
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                duringFocusSeconds: 8 * 60,
                outsideFocusSeconds: 0
            )
        ]

        let visibleEntries = InsightsAppUsagePolicy.visibleEntries(
            from: entries,
            collectRawDomains: true
        )

        XCTAssertEqual(
            visibleEntries.map(\AppUsageEntry.bundleIdentifier),
            entries.map(\AppUsageEntry.bundleIdentifier)
        )
    }

    func testFilterEntriesDropsMalformedDomainRowsWhenRawCaptureEnabled() {
        let visibleEntries = InsightsAppUsagePolicy.visibleEntries(
            from: [
                AppUsageEntry(
                    date: Date(),
                    appName: "Arc",
                    bundleIdentifier: "domain:company.thebrowser.browser",
                    duringFocusSeconds: 12 * 60,
                    outsideFocusSeconds: 0
                ),
                AppUsageEntry(
                    date: Date(),
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    duringFocusSeconds: 8 * 60,
                    outsideFocusSeconds: 0
                )
            ],
            collectRawDomains: true
        )

        XCTAssertEqual(visibleEntries.map(\AppUsageEntry.bundleIdentifier), ["com.apple.Safari"])
    }

    func testDisabledModeSuppressesDomainDrivenWeeklyReportTriggers() {
        let entries = InsightsAppUsagePolicy.visibleEntries(
            from: [
                AppUsageEntry(
                    date: Date(),
                    appName: "YouTube",
                    bundleIdentifier: "domain:youtube.com",
                    duringFocusSeconds: 15 * 60,
                    outsideFocusSeconds: 0
                )
            ],
            collectRawDomains: false
        )

        let report = builder.build(
            sessions: [
                .init(
                    id: UUID(),
                    type: "focus",
                    duration: 1500,
                    startedAt: Date().addingTimeInterval(-1500),
                    endedAt: Date(),
                    completed: true
                )
            ],
            interruptions: [],
            attempts: [],
            appUsage: entries.map {
                FocusCoachInsightsBuilder.AppUsageSnapshot(
                    appName: $0.appName,
                    duringFocusSeconds: $0.duringFocusSeconds,
                    category: $0.category.rawValue
                )
            }
        )

        XCTAssertFalse(report.topTriggers.contains(where: { $0.label == "YouTube" }))
    }

    func testEnabledModeKeepsDomainDrivenWeeklyReportTriggers() {
        let entries = InsightsAppUsagePolicy.visibleEntries(
            from: [
                AppUsageEntry(
                    date: Date(),
                    appName: "YouTube",
                    bundleIdentifier: "domain:youtube.com",
                    duringFocusSeconds: 15 * 60,
                    outsideFocusSeconds: 0
                )
            ],
            collectRawDomains: true
        )

        let report = builder.build(
            sessions: [
                .init(
                    id: UUID(),
                    type: "focus",
                    duration: 1500,
                    startedAt: Date().addingTimeInterval(-1500),
                    endedAt: Date(),
                    completed: true
                )
            ],
            interruptions: [],
            attempts: [],
            appUsage: entries.map {
                FocusCoachInsightsBuilder.AppUsageSnapshot(
                    appName: $0.appName,
                    duringFocusSeconds: $0.duringFocusSeconds,
                    category: $0.category.rawValue
                )
            }
        )

        XCTAssertEqual(report.topTriggers.first?.label, "YouTube")
    }
}
