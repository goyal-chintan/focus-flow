import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class AppUsageCaptureWriterTests: XCTestCase {
    func testRecordBrowserDomainUsageSkipsDomainEntryWhenSettingDisabled() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let writer = AppUsageCaptureWriter()
        let settings = AppSettings()
        var entries: [String: AppUsageEntry] = [:]

        let entry = writer.recordBrowserDomainUsage(
            resolvedHost: "youtube.com",
            settings: settings,
            isFocusing: true
        ) { bundleIdentifier, appName in
            self.entry(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                context: context,
                cache: &entries
            )
        }

        XCTAssertNil(entry)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AppUsageEntry>()).isEmpty)
    }

    func testRecordBrowserDomainUsagePersistsNormalizedDomainEntryWhenSettingEnabled() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let writer = AppUsageCaptureWriter()
        let settings = AppSettings()
        settings.coachCollectRawDomains = true
        var entries: [String: AppUsageEntry] = [:]

        let entry = writer.recordBrowserDomainUsage(
            resolvedHost: "https://www.youtube.com/watch?v=123",
            settings: settings,
            isFocusing: false
        ) { bundleIdentifier, appName in
            self.entry(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                context: context,
                cache: &entries
            )
        }

        XCTAssertEqual(entry?.bundleIdentifier, "domain:youtube.com")
        XCTAssertEqual(entry?.appName, "YouTube")
        XCTAssertEqual(entry?.duringFocusSeconds, 0)
        XCTAssertEqual(entry?.outsideFocusSeconds, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppUsageEntry>()).count, 1)
    }

    func testRecordBrowserDomainUsageRejectsInvalidResolvedHost() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let writer = AppUsageCaptureWriter()
        let settings = AppSettings()
        settings.coachCollectRawDomains = true
        var entries: [String: AppUsageEntry] = [:]

        let entry = writer.recordBrowserDomainUsage(
            resolvedHost: "company.thebrowser.browser",
            settings: settings,
            isFocusing: true
        ) { bundleIdentifier, appName in
            self.entry(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                context: context,
                cache: &entries
            )
        }

        XCTAssertNil(entry)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AppUsageEntry>()).isEmpty)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            AppSettings.self,
            AppUsageEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func entry(
        bundleIdentifier: String,
        appName: String,
        context: ModelContext,
        cache: inout [String: AppUsageEntry]
    ) -> AppUsageEntry {
        if let existing = cache[bundleIdentifier] {
            if existing.appName != appName {
                existing.appName = appName
            }
            return existing
        }

        let entry = AppUsageEntry(
            date: Calendar.current.startOfDay(for: Date()),
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
        context.insert(entry)
        cache[bundleIdentifier] = entry
        return entry
    }
}
