import XCTest

final class ReviewQualityGateTests: XCTestCase {
    func testCriticalViewsAvoidTopMoveTransitions() throws {
        let criticalFiles = [
            "Sources/FocusFlow/Views/SessionCompleteWindow.swift",
            "Sources/FocusFlow/Views/CoachInterventionWindowView.swift",
            "Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift"
        ]

        for file in criticalFiles {
            let source = try loadSource(file)
            XCTAssertFalse(
                source.contains(".move(edge: .top)"),
                "\(file) still uses top-edge translating transitions; use fold/opacity transitions for disclosures."
            )
        }
    }

    func testSessionCompleteBreakPaneUsesStableWidth() throws {
        let source = try loadSource("Sources/FocusFlow/Views/SessionCompleteWindow.swift")
        XCTAssertFalse(
            source.contains(".frame(width: timerVM.showCoachReasonSheet ?"),
            "SessionCompleteWindow break pane width should not jump on first toggle."
        )
    }

    func testCriticalViewsHaveExplicitAccessibilityLabelsForInteractiveControls() throws {
        let criticalFiles = [
            "Sources/FocusFlow/Views/SessionCompleteWindow.swift",
            "Sources/FocusFlow/Views/CoachInterventionWindowView.swift",
            "Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift"
        ]

        for file in criticalFiles {
            let source = try loadSource(file)
            let interactiveCount = countMatches(in: source, regex: #"\b(Button\s*\{|Toggle\s*\(|Stepper\s*\()"#)
            let labelCount = countMatches(in: source, regex: #"\.accessibilityLabel\("#)
            XCTAssertGreaterThanOrEqual(
                labelCount,
                interactiveCount,
                "\(file) has \(interactiveCount) interactive controls but only \(labelCount) explicit accessibility labels."
            )
        }
    }

    func testMenuBarAndCoachDismissControlsMeetMinimumTapTarget() throws {
        let menuBarSource = try loadSource("Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift")
        XCTAssertTrue(
            menuBarSource.contains(".frame(width: 44, height: 44)"),
            "Menu bar header and dismiss controls must use a 44x44 tap target."
        )

        let reasonSheetSource = try loadSource("Sources/FocusFlow/Views/Components/FocusCoachReasonChipSheet.swift")
        XCTAssertTrue(
            reasonSheetSource.contains(".frame(minWidth: 44, minHeight: 44)"),
            "Reason sheet dismiss control must use a minimum 44x44 tap target."
        )
    }

    // MARK: - Helpers

    private func loadSource(_ path: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func countMatches(in text: String, regex pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}
