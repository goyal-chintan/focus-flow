import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class IdleDistractionLegacyCleanupTests: XCTestCase {

    // MARK: - System processes

    func testSystemProcessBundleIdentifiersAreIgnored() {
        XCTAssertTrue(AppUsageTracker.isIgnoredSystemBundleIdentifier("com.apple.loginwindow"))
        XCTAssertTrue(AppUsageTracker.isIgnoredSystemBundleIdentifier("com.apple.ScreenSaver.Engine"))
        XCTAssertTrue(AppUsageTracker.isIgnoredSystemBundleIdentifier("com.apple.UserNotificationCenter"))
        XCTAssertTrue(AppUsageTracker.isIgnoredSystemBundleIdentifier("com.apple.SecurityAgent"))
        XCTAssertTrue(AppUsageTracker.isIgnoredSystemBundleIdentifier("com.apple.dock"))
        XCTAssertFalse(AppUsageTracker.isIgnoredSystemBundleIdentifier("com.apple.Safari"))
    }

    func testSystemProcessRowsAreDeletedWhateverTheirStatus() {
        let manualActive = makeItem(key: "com.apple.loginwindow", kind: .app, source: .manual, status: .active)
        let suggestedPending = makeItem(key: "com.apple.ScreenSaver.Engine", kind: .app, source: .suggested, status: .pending)

        XCTAssertTrue(IdleDistractionLegacyCleanup.shouldDelete(manualActive))
        XCTAssertTrue(IdleDistractionLegacyCleanup.shouldDelete(suggestedPending))
    }

    // MARK: - Work tools

    func testPendingSuggestedWorkToolRowsAreDeleted() {
        let rows = [
            makeItem(key: "acme.atlassian.net", kind: .website, source: .suggested, status: .pending),
            makeItem(key: "github.com", kind: .website, source: .suggested, status: .pending),
            makeItem(key: "mail.google.com", kind: .website, source: .suggested, status: .pending),
            makeItem(key: "com.tinyspeck.slackmacgap", kind: .app, source: .suggested, status: .pending),
            makeItem(key: "com.todesktop.230313mzl4w4u92", kind: .app, source: .suggested, status: .pending),
            makeItem(key: "com.anthropic.claudefordesktop", kind: .app, source: .suggested, status: .pending),
            makeItem(key: "com.jetbrains.intellij", kind: .app, source: .suggested, status: .pending),
        ]

        for row in rows {
            XCTAssertTrue(IdleDistractionLegacyCleanup.shouldDelete(row), "Expected to delete \(row.key)")
        }
    }

    func testManualActiveOrDismissedWorkToolRowsAreKept() {
        let rows = [
            makeItem(key: "github.com", kind: .website, source: .manual, status: .pending),
            makeItem(key: "com.tinyspeck.slackmacgap", kind: .app, source: .manual, status: .active),
            makeItem(key: "github.com", kind: .website, source: .suggested, status: .active),
            makeItem(key: "com.jetbrains.intellij", kind: .app, source: .suggested, status: .dismissed),
        ]

        for row in rows {
            XCTAssertFalse(IdleDistractionLegacyCleanup.shouldDelete(row), "Expected to keep \(row.key)")
        }
    }

    func testNonWorkToolSuggestedRowsAreKept() {
        let rows = [
            makeItem(key: "reddit.com", kind: .website, source: .suggested, status: .pending),
            makeItem(key: "com.spotify.client", kind: .app, source: .suggested, status: .pending),
        ]

        for row in rows {
            XCTAssertFalse(IdleDistractionLegacyCleanup.shouldDelete(row), "Expected to keep \(row.key)")
        }
    }

    // MARK: - One-time run

    func testRunOnceDeletesMatchingRowsAndOnlyRunsOnce() throws {
        let container = try ModelContainer(
            for: IdleDistractionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let suiteName = "IdleDistractionLegacyCleanupTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        context.insert(makeItem(key: "com.apple.dock", kind: .app, source: .manual, status: .active))
        context.insert(makeItem(key: "github.com", kind: .website, source: .suggested, status: .pending))
        context.insert(makeItem(key: "reddit.com", kind: .website, source: .suggested, status: .pending))
        try context.save()

        let firstCount = IdleDistractionLegacyCleanup.runOnce(in: context, defaults: defaults)
        XCTAssertEqual(firstCount, 2)

        let remaining = try context.fetch(FetchDescriptor<IdleDistractionItem>())
        XCTAssertEqual(remaining.map(\.key), ["reddit.com"])

        // A later launch must not re-run the cleanup against rows created after the first run.
        context.insert(makeItem(key: "github.com", kind: .website, source: .suggested, status: .pending))
        try context.save()
        let secondCount = IdleDistractionLegacyCleanup.runOnce(in: context, defaults: defaults)
        XCTAssertEqual(secondCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<IdleDistractionItem>()), 2)
    }

    // MARK: - Helpers

    private func makeItem(
        key: String,
        kind: IdleDistractionTargetKind,
        source: IdleDistractionSource,
        status: IdleDistractionStatus
    ) -> IdleDistractionItem {
        IdleDistractionItem(
            key: key,
            displayName: key,
            targetKind: kind,
            severity: .minor,
            source: source,
            status: status
        )
    }
}
