import XCTest
import AppKit
@testable import FocusFlow

/// 7 Nov 2026: the block-end window opened small, behind other apps, on another screen.
@MainActor
final class BlockEndWindowTests: XCTestCase {
    func testItOpensUsableCentredAndFitsTheScreen() {
        let screen = NSRect(x: 1440, y: 0, width: 1728, height: 1080)
        let f = BlockEndWindowPresenter.frame(saved: nil, visible: screen)
        XCTAssertEqual(f.size, NSSize(width: 560, height: 760))
        XCTAssertEqual(f.midX, screen.midX, "On the screen you're on, centred")
        let small = BlockEndWindowPresenter.frame(saved: nil, visible: NSRect(x: 0, y: 0, width: 1280, height: 700))
        XCTAssertEqual(small.height, 660, "Never taller than the screen")
        XCTAssertEqual(BlockEndWindowPresenter.frame(saved: NSSize(width: 700, height: 900), visible: screen).size, NSSize(width: 700, height: 900), "Your size is kept")
        XCTAssertEqual(BlockEndWindowPresenter.frame(saved: NSSize(width: 300, height: 200), visible: screen).size, NSSize(width: 560, height: 760), "A too-small size is ignored")
        XCTAssertEqual(BlockEndWindowPresenter.frame(saved: NSSize(width: 700, height: 900), visible: screen, compact: true).size, NSSize(width: 480, height: 560))
    }

    func testTheSceneIsResizableAndTheWindowNoLongerCentresInPlace() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/FocusFlowApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains(".defaultSize(width: 560, height: 760)"))
        let view = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/SessionCompleteWindow.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("BlockEndWindowPresenter.present("))
        XCTAssertFalse(view.contains("window.center()"), "center() kept it on whatever screen it was last on")
        XCTAssertFalse(view.contains(".frame(maxHeight: 620)"), "The content fills the window, not a 620 pt cap")
    }
}
