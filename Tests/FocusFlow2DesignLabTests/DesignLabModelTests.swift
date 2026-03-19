import XCTest
@testable import FocusFlow2

final class DesignLabModelTests: XCTestCase {
    func testBuildInfoReadsBundleKeysAndFallsBackToBundleVersion() {
        let keyed = FFBuildInfo(bundleInfo: [
            "FFBuildSHA": "6b4c7d9",
            "FFBuildTimestampUTC": "20260319T121500Z"
        ])
        XCTAssertEqual(keyed.shortGitSHA, "6b4c7d9")
        XCTAssertEqual(keyed.timestampUTC, "20260319T121500Z")
        XCTAssertEqual(keyed.displayString, "6b4c7d9 · 20260319T121500Z")

        let fallback = FFBuildInfo(bundleInfo: [
            "CFBundleVersion": "86d678a"
        ])
        XCTAssertEqual(fallback.shortGitSHA, "86d678a")
        XCTAssertEqual(fallback.timestampUTC, "unknown")
        XCTAssertEqual(fallback.displayString, "86d678a · unknown")
    }

    func testScenarioSnapshotsCycleEveryThreeSteps() {
        for scenario in VariantLabScenario.allCases {
            let snapshot0 = scenario.snapshot(transitionStep: 0)
            let snapshot3 = scenario.snapshot(transitionStep: 3)
            let snapshot6 = scenario.snapshot(transitionStep: 6)

            XCTAssertEqual(snapshot0.stateLabel, snapshot3.stateLabel)
            XCTAssertEqual(snapshot0.stateLabel, snapshot6.stateLabel)
            XCTAssertEqual(snapshot0.timerText, snapshot3.timerText)
            XCTAssertEqual(snapshot0.primaryAction, snapshot3.primaryAction)
            XCTAssertEqual(snapshot0.secondaryAction, snapshot3.secondaryAction)
            XCTAssertFalse(snapshot0.footer.isEmpty)
            XCTAssertEqual(snapshot0.chips.count, 2)
        }
    }

    func testSharedBackdropStylesIncludeTextureForTransparencyReview() {
        XCTAssertEqual(FFLabBackdropStyle.allCases.count, 4)
        XCTAssertTrue(FFLabBackdropStyle.allCases.contains(.texture))
        XCTAssertEqual(FFLabBackdropStyle.texture.rawValue, "Texture")
    }

    func testVariantLabSourceDoesNotContainStandaloneLayoutBenchSections() throws {
        let sourceURL = URL(fileURLWithPath: "/Users/chintan/Personal/repos/FocusFlow/.worktrees/codex/premium-ui-redesign/Sources/FocusFlow2/Views/VariantLab/VariantLabView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("Layout Bench"))
        XCTAssertFalse(source.contains("Layout Finalization"))
    }

    func testLayoutReviewUsesFiveDedicatedVariants() {
        XCTAssertEqual(VariantLabLayoutVariant.allCases.count, 5)
        XCTAssertEqual(VariantLabLayoutVariant.allCases.map(\.rawValue), ["A", "B", "C", "D", "E"])
    }

    func testDecisionRecordMarkdownIsDeterministic() {
        let record = VariantLabDecisionRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            roundName: "2",
            scenario: .running,
            component: .motion,
            variant: VariantLabMenuVariant.variantB.rawValue,
            motionSpeed: .x15,
            action: .needsTweak,
            notes: "Reduce glow radius and calm the press response.",
            interaction: VariantLabInteractionSnapshot(
                isExpanded: true,
                hoverPreview: false,
                pressPreview: true,
                transitionStep: 2
            )
        )

        let first = record.markdownEntry
        let second = record.markdownEntry

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("Round 2"))
        XCTAssertTrue(first.contains("Scenario: Running"))
        XCTAssertTrue(first.contains("Component: Motion"))
        XCTAssertTrue(first.contains("Variant: B"))
        XCTAssertTrue(first.contains("Action: Needs tweak"))
        XCTAssertTrue(first.contains("Motion: 1.5x"))
        XCTAssertTrue(first.contains("open=true, hover=false, press=true, transition=2"))
        XCTAssertTrue(first.contains("Reduce glow radius"))
        XCTAssertFalse(first.contains("Ratings"))
    }

    func testTokenCopyAndApplyAreIdempotent() {
        let original = FFDesignTokens()
        let baseline = original.copy()

        let tuned = makeTunedTokens(from: original)
        let firstPass = baseline.copy()
        firstPass.apply(from: tuned)

        let secondPass = firstPass.copy()
        secondPass.apply(from: tuned)

        XCTAssertEqual(firstPass, secondPass)

        let reverted = secondPass.copy()
        reverted.apply(from: original)

        XCTAssertEqual(reverted, original)
        XCTAssertEqual(original, baseline)
    }

    func testTokenCodableRoundTripIsStable() throws {
        let tokens = makeTunedTokens(from: FFDesignTokens())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        let firstData = try encoder.encode(tokens)
        let secondData = try encoder.encode(tokens)
        let decoded = try JSONDecoder().decode(FFDesignTokens.self, from: firstData)
        let firstString = try XCTUnwrap(String(data: firstData, encoding: .utf8))
        let secondString = try XCTUnwrap(String(data: secondData, encoding: .utf8))

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(firstString, secondString)
        XCTAssertEqual(decoded, tokens)
    }

    private func makeTunedTokens(from tokens: FFDesignTokens) -> FFDesignTokens {
        let tuned = tokens.copy()
        tuned.spacing.md = 20
        tuned.radius.card = 22
        tuned.sizing.controlMin = 48
        tuned.ring.size = 212
        tuned.ring.strokeWidth = 5.5
        tuned.ring.timerFontSize = 64
        tuned.ring.labelFontSize = 15
        tuned.ring.glowRadius = 12
        tuned.typography.heroLabelSize = 15
        tuned.typography.titleSize = 17
        tuned.color.panelFillOpacity = 0.07
        tuned.color.panelBorderOpacity = 0.12
        tuned.motion.popoverResponse = 0.40
        tuned.motion.controlDamping = 0.86
        tuned.layout.popoverWidth = 360
        return tuned
    }
}
