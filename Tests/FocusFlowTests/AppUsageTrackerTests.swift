import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class AppUsageTrackerTests: XCTestCase {
    func testFrontmostBrowserContextSanitizesBrowserCoachingSignalsWhenDomainCaptureDisabled() {
        let settings = AppSettings()
        settings.coachCollectRawDomains = false

        let context = AppUsageTracker.frontmostContextPresentation(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Sorting Algorithms - YouTube",
            resolvedBrowserHost: "https://www.youtube.com/watch?v=123",
            settings: settings
        )

        XCTAssertNil(context.browserHost)
        XCTAssertNil(context.domainLabel)
        XCTAssertEqual(context.displayLabel, "Safari")
        XCTAssertEqual(context.effectiveWindowTitle, "Safari")
        XCTAssertEqual(context.category, .neutral)
    }

    func testFrontmostBrowserContextExposesFriendlyDomainWhenDomainCaptureEnabled() {
        let settings = AppSettings()
        settings.coachCollectRawDomains = true

        let context = AppUsageTracker.frontmostContextPresentation(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Sorting Algorithms - YouTube",
            resolvedBrowserHost: "https://www.youtube.com/watch?v=123",
            settings: settings
        )

        XCTAssertEqual(context.browserHost, "youtube.com")
        XCTAssertEqual(context.domainLabel, "YouTube")
        XCTAssertEqual(context.displayLabel, "YouTube")
        XCTAssertEqual(context.effectiveWindowTitle, "Sorting Algorithms - YouTube")
        XCTAssertEqual(context.category, .distracting)
    }

    func testFrontmostBrowserContextDefaultsToAppLabelWithoutSettings() {
        let context = AppUsageTracker.frontmostContextPresentation(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "YouTube",
            resolvedBrowserHost: "youtube.com",
            settings: nil
        )

        XCTAssertNil(context.browserHost)
        XCTAssertNil(context.domainLabel)
        XCTAssertEqual(context.displayLabel, "Safari")
        XCTAssertEqual(context.effectiveWindowTitle, "Safari")
        XCTAssertEqual(context.category, .neutral)
    }

    func testHydratedFocusTotalsExcludePersistedDomainRowsFromTotalButUseThemForDistractingFocus() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                duringFocusSeconds: 1200,
                outsideFocusSeconds: 0
            ),
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 900,
                outsideFocusSeconds: 0
            ),
            AppUsageEntry(
                date: Date(),
                appName: "Reddit",
                bundleIdentifier: "com.reddit.Reddit",
                duringFocusSeconds: 300,
                outsideFocusSeconds: 0
            )
        ]

        let totals = AppUsageTracker.focusTotals(for: entries)
        XCTAssertEqual(totals.totalFocusSeconds, 1500)
        XCTAssertEqual(totals.distractingFocusSeconds, 1200)
    }

    func testObservationProjectScopeDropsRestoredProjectWhenIdle() {
        let scope = AppUsageTracker.observationProjectScope(
            isInSession: false,
            selectedProjectId: UUID(),
            selectedProjectName: "Office",
            selectedWorkMode: .deepWork
        )

        XCTAssertNil(scope.selectedProjectId)
        XCTAssertNil(scope.selectedProjectName)
        XCTAssertNil(scope.selectedWorkMode)
    }

    func testObservationProjectScopeKeepsProjectDuringActiveSession() {
        let projectId = UUID()

        let scope = AppUsageTracker.observationProjectScope(
            isInSession: true,
            selectedProjectId: projectId,
            selectedProjectName: "Office",
            selectedWorkMode: .deepWork
        )

        XCTAssertEqual(scope.selectedProjectId, projectId)
        XCTAssertEqual(scope.selectedProjectName, "Office")
        XCTAssertEqual(scope.selectedWorkMode, .deepWork)
    }

    func testIdleFrontmostContextUsesAcceptedIdleRuleInsteadOfRestoredProjectAllowance() {
        let settings = AppSettings()

        let context = AppUsageTracker.frontmostContextPresentation(
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            windowTitle: "Ghostty",
            resolvedBrowserHost: nil,
            settings: settings,
            idleSeverityOverride: .major
        )

        XCTAssertEqual(context.category, .distracting)
    }

    func testUsageMutationsAreBatchedUntilPersistIntervalElapses() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())
        tracker.testingSetLastPersistAt(Date())

        tracker.testingRecordUsageDelta(bundleId: "com.apple.Safari", appName: "Safari", isFocusing: true)
        tracker.testingRecordUsageDelta(bundleId: "com.apple.Safari", appName: "Safari", isFocusing: true)
        tracker.testingRecordUsageDelta(bundleId: "com.apple.Safari", appName: "Safari", isFocusing: false)

        XCTAssertEqual(try context.fetch(FetchDescriptor<AppUsageEntry>()).count, 0)

        tracker.testingPersistIfNeeded(force: false)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppUsageEntry>()).count, 0)
        XCTAssertEqual(tracker.testingPendingDeltaCount, 1)

        tracker.testingSetLastPersistAt(Date().addingTimeInterval(-31))
        tracker.testingPersistIfNeeded(force: false)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.duringFocusSeconds, 2)
        XCTAssertEqual(entries.first?.outsideFocusSeconds, 1)
        XCTAssertEqual(tracker.testingPendingDeltaCount, 0)
    }

    func testForcedPersistFlushesAllPendingDeltasWithCorrectCounters() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())

        tracker.testingRecordUsageDelta(bundleId: "com.apple.Safari", appName: "Safari", isFocusing: true)
        tracker.testingRecordUsageDelta(bundleId: "com.apple.Safari", appName: "Safari", isFocusing: false)
        tracker.testingRecordUsageDelta(bundleId: "domain:youtube.com", appName: "YouTube", isFocusing: true)
        tracker.testingPersistIfNeeded(force: true)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 2)

        let safari = entries.first(where: { $0.bundleIdentifier == "com.apple.Safari" })
        XCTAssertEqual(safari?.duringFocusSeconds, 1)
        XCTAssertEqual(safari?.outsideFocusSeconds, 1)

        let domain = entries.first(where: { $0.bundleIdentifier == "domain:youtube.com" })
        XCTAssertEqual(domain?.duringFocusSeconds, 1)
        XCTAssertEqual(domain?.outsideFocusSeconds, 0)
        XCTAssertEqual(tracker.testingPendingDeltaCount, 0)
    }

    func testPersistFailurePreservesPendingDeltasForRetry() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())

        tracker.testingRecordUsageDelta(bundleId: "com.apple.Safari", appName: "Safari", isFocusing: true)
        tracker.testingFailNextSave()

        tracker.testingPersistIfNeeded(force: true)
        XCTAssertEqual(tracker.testingPendingDeltaCount, 1)

        tracker.testingPersistIfNeeded(force: true)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.duringFocusSeconds, 1)
        XCTAssertEqual(entries.first?.outsideFocusSeconds, 0)
        XCTAssertEqual(tracker.testingPendingDeltaCount, 0)
    }

    func testTrackingCadenceIsPrecisionDuringFocus() {
        let cadence = AppUsageTracker.TrackingCadence.forState(isFocusing: true)
        XCTAssertEqual(cadence, .precision)
        XCTAssertEqual(cadence.interval, 1.0)
    }

    func testTrackingCadenceIsEcoOutsideFocus() {
        let cadence = AppUsageTracker.TrackingCadence.forState(isFocusing: false)
        XCTAssertEqual(cadence, .eco)
        XCTAssertEqual(cadence.interval, 4.0)
    }

    func testBrowserRefreshIntervalIsShortDuringFocus() {
        let interval = AppUsageTracker.TrackingCadence.precision.browserRefreshInterval
        XCTAssertEqual(interval, 12.0)
    }

    func testBrowserRefreshIntervalIsLongOutsideFocus() {
        let interval = AppUsageTracker.TrackingCadence.eco.browserRefreshInterval
        XCTAssertEqual(interval, 30.0)
    }

    func testEcoCadencePersistsOutsideFocusUsageForFullTickDuration() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())

        tracker.testingRecordUsageDelta(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            isFocusing: false,
            seconds: Int(AppUsageTracker.TrackingCadence.eco.interval)
        )
        tracker.testingPersistIfNeeded(force: true)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.duringFocusSeconds, 0)
        XCTAssertEqual(entries.first?.outsideFocusSeconds, 4)
    }

    func testPrecisionCadencePersistsFocusUsageForSingleSecond() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())

        tracker.testingRecordUsageDelta(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            isFocusing: true,
            seconds: Int(AppUsageTracker.TrackingCadence.precision.interval)
        )
        tracker.testingPersistIfNeeded(force: true)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.duringFocusSeconds, 1)
        XCTAssertEqual(entries.first?.outsideFocusSeconds, 0)
    }

    func testBrowserRefreshGateSkipsSameAppBeforeEcoIntervalElapses() {
        let now = Date()

        let shouldRefresh = AppUsageTracker.shouldRefreshBrowserContext(
            bundleId: "com.apple.Safari",
            lastFrontmostBundleId: "com.apple.Safari",
            now: now,
            lastRefreshAt: now.addingTimeInterval(-10),
            cadence: .eco
        )

        XCTAssertFalse(shouldRefresh)
    }

    func testBrowserRefreshGateRefreshesSameAppAfterEcoIntervalElapses() {
        let now = Date()

        let shouldRefresh = AppUsageTracker.shouldRefreshBrowserContext(
            bundleId: "com.apple.Safari",
            lastFrontmostBundleId: "com.apple.Safari",
            now: now,
            lastRefreshAt: now.addingTimeInterval(-31),
            cadence: .eco
        )

        XCTAssertTrue(shouldRefresh)
    }

    func testBrowserAppSwitchBypassesRefreshIntervalGate() {
        let now = Date()

        let shouldRefresh = AppUsageTracker.shouldRefreshBrowserContext(
            bundleId: "com.google.Chrome",
            lastFrontmostBundleId: "com.apple.Safari",
            now: now,
            lastRefreshAt: now,
            cadence: .eco
        )

        XCTAssertTrue(shouldRefresh)
    }

    func testSyncCadenceSwitchesTrackerImmediatelyWhenFocusStateChanges() {
        let tracker = AppUsageTracker.makeForTesting()

        tracker.testingSetIsTracking(true)
        tracker.testingSetCurrentCadence(.eco)
        tracker.syncCadence(isFocusing: true)

        XCTAssertEqual(tracker.testingCurrentCadence, .precision)
    }

    func testFlushElapsedSampleCreditsElapsedFocusSecondsAcrossCadenceChange() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())
        tracker.testingSetFrontmostContext(bundleId: "com.apple.Safari", appName: "Safari")
        tracker.testingSetCurrentCadence(.precision)
        tracker.testingSetLastSampleAt(Date().addingTimeInterval(-3.2))

        tracker.testingFlushElapsedSample(isFocusing: true, now: Date())
        tracker.testingPersistIfNeeded(force: true)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.duringFocusSeconds, 3)
    }

    func testFlushElapsedSampleCreditsElapsedIdleSecondsAcrossCadenceChange() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())
        tracker.testingSetFrontmostContext(bundleId: "com.apple.Safari", appName: "Safari")
        tracker.testingSetCurrentCadence(.eco)
        tracker.testingSetLastSampleAt(Date().addingTimeInterval(-2.4))

        tracker.testingFlushElapsedSample(isFocusing: false, now: Date())
        tracker.testingPersistIfNeeded(force: true)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outsideFocusSeconds, 2)
    }

    func testSyncCadenceAttributesElapsedSecondsToPreviousState() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let tracker = AppUsageTracker.makeForTesting()
        tracker.testingConfigurePersistence(modelContext: context, day: Date())
        tracker.testingSetIsTracking(true)
        tracker.testingSetCurrentCadence(.eco)
        tracker.testingSetFrontmostContext(bundleId: "com.apple.Safari", appName: "Safari")
        tracker.testingSetLastSampleAt(Date().addingTimeInterval(-2.7))

        tracker.syncCadence(isFocusing: true)
        tracker.testingPersistIfNeeded(force: true)

        let entries = try context.fetch(FetchDescriptor<AppUsageEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outsideFocusSeconds, 2)
        XCTAssertEqual(entries.first?.duringFocusSeconds, 0)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            AppSettings.self,
            AppUsageEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
