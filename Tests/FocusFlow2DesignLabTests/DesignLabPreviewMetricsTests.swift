import XCTest
@testable import FocusFlow2

final class DesignLabPreviewMetricsTests: XCTestCase {
    func testButtonChromeUsesCapsuleAndReflectsSizingTokens() {
        let tokens = FFDesignTokens()

        let chrome = DesignLabPreviewMetrics.buttonChrome(tokens: tokens, variant: .a)

        XCTAssertEqual(chrome.shape, .capsule)
        XCTAssertEqual(chrome.controlHeight, 44)
        XCTAssertEqual(chrome.iconFrame, 48)
        XCTAssertGreaterThan(chrome.primaryTintOpacity, chrome.secondaryTintOpacity)
        XCTAssertTrue(chrome.badges.contains("Min 44"))
        XCTAssertTrue(chrome.badges.contains("Icon 48"))
    }

    func testButtonChromeBadgesChangeWhenSizingAndTypographyChange() {
        let base = FFDesignTokens()
        let tuned = FFDesignTokens()
        tuned.sizing.controlMin = 56
        tuned.sizing.iconFrame = 60
        tuned.radius.control = 16
        tuned.radius.card = 24
        tuned.spacing.md = 22
        tuned.typography.calloutSize = 18
        tuned.typography.metaSize = 15
        tuned.typography.calloutWeight = .bold
        tuned.typography.metaWeight = .regular

        let baseChrome = DesignLabPreviewMetrics.buttonChrome(tokens: base, variant: .b)
        let tunedChrome = DesignLabPreviewMetrics.buttonChrome(tokens: tuned, variant: .b)

        XCTAssertNotEqual(baseChrome.badges, tunedChrome.badges)
        XCTAssertTrue(tunedChrome.badges.contains("Min 56"))
        XCTAssertTrue(tunedChrome.badges.contains("Icon 60"))
        XCTAssertTrue(tunedChrome.badges.contains("Radius 16"))
        XCTAssertTrue(tunedChrome.badges.contains("Card 24"))
        XCTAssertTrue(tunedChrome.badges.contains("Spacing 22"))
    }

    func testMaterialCuesExposeAllMaterialSliders() {
        let tokens = FFDesignTokens()
        let cues = DesignLabPreviewMetrics.materialCues(tokens: tokens)
        let tuned = FFDesignTokens()
        tuned.color.panelFillOpacity = 0.22
        tuned.color.panelBorderOpacity = 0.18
        tuned.color.panelHighlightOpacity = 0.14
        tuned.color.insetFillOpacity = 0.09
        tuned.color.rowFillOpacity = 0.08
        tuned.color.fieldFillOpacity = 0.24
        tuned.color.fieldBorderOpacity = 0.19
        let tunedCues = DesignLabPreviewMetrics.materialCues(tokens: tuned)

        XCTAssertEqual(cues.count, 7)
        XCTAssertTrue(cues.contains("Fill 0.0"))
        XCTAssertTrue(cues.contains("Border 0.1"))
        XCTAssertTrue(cues.contains("Highlight 0.1"))
        XCTAssertTrue(cues.contains("Inset 0.1"))
        XCTAssertTrue(cues.contains("Row 0.0"))
        XCTAssertTrue(cues.contains("Field 0.1"))
        XCTAssertTrue(cues.contains("Field Border 0.1"))
        XCTAssertNotEqual(cues, tunedCues)
        XCTAssertTrue(tunedCues.contains("Fill 0.2"))
        XCTAssertTrue(tunedCues.contains("Border 0.2"))
        XCTAssertTrue(tunedCues.contains("Field 0.2"))
    }

    func testRingCuesExposeAllRingSliders() {
        let tokens = FFDesignTokens()
        let cues = DesignLabPreviewMetrics.ringCues(tokens: tokens)
        let tuned = FFDesignTokens()
        tuned.ring.size = 240
        tuned.ring.strokeWidth = 8.4
        tuned.ring.timerFontSize = 72
        tuned.ring.timerFontWeight = .bold
        tuned.ring.labelFontSize = 18
        tuned.ring.labelFontWeight = .medium
        tuned.ring.digitTracking = 1.8
        tuned.ring.labelTracking = 1.6
        tuned.ring.backgroundDiscOpacity = 0.12
        tuned.ring.trackOpacity = 0.28
        tuned.ring.glowRadius = 14
        tuned.ring.glowOpacity = 0.72
        let tunedCues = DesignLabPreviewMetrics.ringCues(tokens: tuned)

        XCTAssertEqual(cues.count, 8)
        XCTAssertTrue(cues.contains("Size 198"))
        XCTAssertTrue(cues.contains("Stroke 4.2"))
        XCTAssertTrue(cues.contains("Timer 60 regular"))
        XCTAssertTrue(cues.contains("Label 14 semibold"))
        XCTAssertTrue(cues.contains("Tracking 1 / 1.2"))
        XCTAssertTrue(cues.contains("Glow 10 / 0.5"))
        XCTAssertTrue(cues.contains("Disc 0.0"))
        XCTAssertTrue(cues.contains("Track 0.1"))
        XCTAssertNotEqual(cues, tunedCues)
        XCTAssertTrue(tunedCues.contains("Size 240"))
        XCTAssertTrue(tunedCues.contains("Stroke 8.4"))
        XCTAssertTrue(tunedCues.contains("Timer 72 bold"))
        XCTAssertTrue(tunedCues.contains("Label 18 medium"))
        XCTAssertTrue(tunedCues.contains("Tracking 1.8 / 1.6"))
        XCTAssertTrue(tunedCues.contains("Glow 14 / 0.7"))
        XCTAssertTrue(tunedCues.contains("Disc 0.1"))
        XCTAssertTrue(tunedCues.contains("Track 0.3"))
    }

    func testMotionCuesExposeAllMotionSliders() {
        let tokens = FFDesignTokens()
        let cues = DesignLabPreviewMetrics.motionCues(tokens: tokens)
        let tuned = FFDesignTokens()
        tuned.motion.popoverResponse = 1.3
        tuned.motion.popoverDamping = 0.96
        tuned.motion.sectionResponse = 1.1
        tuned.motion.sectionDamping = 0.88
        tuned.motion.controlResponse = 0.54
        tuned.motion.controlDamping = 0.79
        tuned.motion.breathingDuration = 2.4
        let tunedCues = DesignLabPreviewMetrics.motionCues(tokens: tuned)

        XCTAssertEqual(cues.count, 4)
        XCTAssertTrue(cues.contains("Popover 0.3 / 0.8"))
        XCTAssertTrue(cues.contains("Section 0.3 / 0.8"))
        XCTAssertTrue(cues.contains("Control 0.2 / 0.8"))
        XCTAssertTrue(cues.contains("Breathing 1.8"))
        XCTAssertNotEqual(cues, tunedCues)
        XCTAssertTrue(tunedCues.contains("Popover 1.3 / 1.0"))
        XCTAssertTrue(tunedCues.contains("Section 1.1 / 0.9"))
        XCTAssertTrue(tunedCues.contains("Control 0.5 / 0.8"))
        XCTAssertTrue(tunedCues.contains("Breathing 2.4"))
    }
}
