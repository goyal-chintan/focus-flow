import XCTest
import AppKit
@testable import FocusFlow

/// Settings → General → Appearance: System / Light / Dark, saved and applied app-wide.
final class AppAppearanceTests: XCTestCase {
    func testNothingSavedFollowsTheSystem() {
        let defaults = cleanDefaults("appearance.default")
        XCTAssertEqual(AppAppearance.stored(in: defaults), .system)
        XCTAssertNil(AppAppearance.system.nsAppearance)
    }

    func testAnUnknownSavedValueFollowsTheSystem() {
        let defaults = cleanDefaults("appearance.unknown")
        defaults.set("sepia", forKey: AppAppearance.storageKey)
        XCTAssertEqual(AppAppearance.stored(in: defaults), .system)
    }

    func testLightAndDarkMapToAquaAndDarkAqua() {
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
    }

    @MainActor
    func testApplyingSetsTheAppAppearance() {
        let original = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = original }
        AppAppearance.apply(.dark)
        XCTAssertEqual(NSApplication.shared.appearance?.name, .darkAqua)
        AppAppearance.apply(.light)
        XCTAssertEqual(NSApplication.shared.appearance?.name, .aqua)
        AppAppearance.apply(.system)
        XCTAssertNil(NSApplication.shared.appearance)
    }

    @MainActor
    func testLaunchAppliesTheSavedChoice() {
        let original = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = original }
        let defaults = cleanDefaults("appearance.launch")
        defaults.set(AppAppearance.dark.rawValue, forKey: AppAppearance.storageKey)
        AppAppearance.applyStored(defaults: defaults)
        XCTAssertEqual(NSApplication.shared.appearance?.name, .darkAqua)
    }
}
