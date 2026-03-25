import XCTest
@testable import FocusFlow

final class ReviewContractsTests: XCTestCase {
    func testProjectFormDropdownRowsHaveFullWidthHitTargets() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("ProjectFormView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var blockProfileSection"))
        XCTAssertTrue(source.contains("private var workModeSection"))
        XCTAssertTrue(source.contains("private var guardianSensitivitySection"))
        XCTAssertTrue(source.contains("private var difficultyBiasSection"))

        // Each dropdown row should provide a full-row hit target, not only text/chevron.
        let hitTargetPattern = try NSRegularExpression(
            pattern: #"\.frame\(maxWidth:\s*\.infinity,\s*alignment:\s*\.leading\)\s*[\r\n\s]*\.contentShape\(Rectangle\(\)\)"#
        )
        let matches = hitTargetPattern.numberOfMatches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        XCTAssertGreaterThanOrEqual(matches, 4, "Expected full-row hit target pattern on all project-form dropdown rows")
    }

    func testReviewArtifactContractCoversAllCriticalFlows() {
        let expectedFlowIDs: Set<String> = [
            "menu_bar_idle",
            "menu_bar_focusing",
            "menu_bar_paused",
            "menu_bar_overtime",
            "menu_bar_break_overrun",
            "session_complete_focus_complete",
            "session_complete_manual_stop",
            "session_complete_break_complete",
            "session_complete_earned_stage",
            "session_complete_recovery_chips",
            "coach_quick_prompt",
            "coach_strong_window",
            "coach_window_dismiss",
            "settings_calendar_permissions",
            "settings_reminders_permissions",
            "today_stats_view",
            "break_complete_reason_sheet_hidden",
            "break_complete_reason_sheet_visible"
        ]

        let actualFlowIDs = Set(ReviewArtifactContract.requiredFlowIDs)
        XCTAssertEqual(actualFlowIDs, expectedFlowIDs)
    }

    func testReviewArtifactContractBuildsLightAndDarkArtifactPaths() {
        let runID = "sample-run"
        let light = ReviewArtifactContract.requiredArtifactPaths(runID: runID, appearance: .light)
        let dark = ReviewArtifactContract.requiredArtifactPaths(runID: runID, appearance: .dark)

        XCTAssertEqual(light.count, ReviewArtifactContract.requiredFlowIDs.count)
        XCTAssertEqual(dark.count, ReviewArtifactContract.requiredFlowIDs.count)
        XCTAssertTrue(light.allSatisfy { $0.contains("/light/") })
        XCTAssertTrue(dark.allSatisfy { $0.contains("/dark/") })
    }

    func testFlowFixtureSeedContractIncludesCanonicalJourneys() {
        let expectedJourneyIDs: Set<String> = [
            "focus_start_pause_resume_stop",
            "completion_take_break_continue_end",
            "idle_escalation_to_strong_prompt",
            "calendar_event_write_and_update",
            "reminder_create_edit_complete_delete"
        ]

        let actualJourneyIDs = Set(FlowFixtureSeedContract.canonicalFlowIDs)
        XCTAssertEqual(actualJourneyIDs, expectedJourneyIDs)
        XCTAssertEqual(
            Set(FlowFixtureSeedContract.requiredSeedKeys),
            Set(["projects", "sessions", "reminders", "appUsageEntries", "coachRiskLevels"])
        )
    }

    func testAccessibilityContractListsCriticalControlsWithLabels() {
        let controls = AccessibilityContract.criticalControls
        XCTAssertFalse(controls.isEmpty)
        XCTAssertTrue(controls.allSatisfy { !$0.id.isEmpty })
        XCTAssertTrue(controls.allSatisfy { !$0.label.isEmpty })
    }

    func testMotionGeometryContractDefinesTransitionAndBaselineCoverage() {
        XCTAssertFalse(MotionGeometryContract.transitionIntents.isEmpty)
        XCTAssertFalse(MotionGeometryContract.geometryBaselines.isEmpty)
        XCTAssertTrue(MotionGeometryContract.transitionIntents.keys.contains("SessionComplete.coachReasonDisclosure"))
        XCTAssertTrue(MotionGeometryContract.geometryBaselines.keys.contains("SessionComplete.breakPane"))
    }
}
