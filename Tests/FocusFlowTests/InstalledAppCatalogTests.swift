import Foundation
import Testing
@testable import FocusFlow

@Suite("InstalledAppCatalog")
struct InstalledAppCatalogTests {
    @Test("Application directories include the user Applications fallback")
    func applicationDirectoriesIncludeUserFallback() {
        let fakeHome = URL(fileURLWithPath: "/tmp/focusflow-test-home", isDirectory: true)

        let directories = InstalledAppCatalog.applicationDirectories(homeDirectory: fakeHome)

        #expect(directories.contains(fakeHome.appendingPathComponent("Applications", isDirectory: true)))
    }

    @Test("Installed app catalog enumerates app bundles from provided roots")
    func installedAppsEnumerateProvidedRoots() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let appBundle = tempRoot.appendingPathComponent("FocusFlow Fixture.app", isDirectory: true)
        let contentsDirectory = appBundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDirectory, withIntermediateDirectories: true)

        let infoPlistURL = contentsDirectory.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.focusflow.fixture",
            "CFBundleName": "FocusFlow Fixture"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: infoPlistURL)

        let apps = InstalledAppCatalog.installedApps(in: [tempRoot])

        #expect(apps.contains { $0.bundleID == "com.focusflow.fixture" && $0.name == "FocusFlow Fixture" })
    }
}
