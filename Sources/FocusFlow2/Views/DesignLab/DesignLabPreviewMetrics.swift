import Foundation
import SwiftUI

enum DesignLabPreviewMetrics {
    static func buttonChrome(tokens: FFDesignTokens, variant: DesignLabVariant) -> DesignLabButtonChrome {
        let controlHeight = max(40, tokens.sizing.controlMin)
        let iconFrame = max(28, tokens.sizing.iconFrame)
        let containerRadius = max(tokens.radius.card, controlHeight * 0.42)
        let titleSize = max(11, tokens.typography.calloutSize)
        let subtitleSize = max(10, tokens.typography.metaSize)
        let titleWeight = tokens.typography.calloutWeight
        let subtitleWeight = tokens.typography.metaWeight

        let variantTintAdjustment: Double = switch variant {
        case .a: 0.02
        case .b: 0.00
        case .c: -0.02
        }

        return DesignLabButtonChrome(
            shape: .capsule,
            controlHeight: controlHeight,
            iconFrame: iconFrame,
            containerRadius: containerRadius,
            titleSize: titleSize,
            subtitleSize: subtitleSize,
            titleWeight: titleWeight,
            subtitleWeight: subtitleWeight,
            primaryTintOpacity: max(0.42, min(0.82, 0.75 + variantTintAdjustment)),
            secondaryTintOpacity: max(0.30, min(0.55, 0.44 + variantTintAdjustment)),
            badges: [
                "Min \(format(controlHeight))",
                "Icon \(format(iconFrame))",
                "Radius \(format(tokens.radius.control))",
                "Card \(format(tokens.radius.card))",
                "Callout \(format(titleSize)) \(titleWeight.rawValue)",
                "Meta \(format(subtitleSize)) \(subtitleWeight.rawValue)",
                "Spacing \(format(tokens.spacing.md))"
            ]
        )
    }

    static func materialCues(tokens: FFDesignTokens) -> [String] {
        [
            "Fill \(format(tokens.color.panelFillOpacity))",
            "Border \(format(tokens.color.panelBorderOpacity))",
            "Highlight \(format(tokens.color.panelHighlightOpacity))",
            "Inset \(format(tokens.color.insetFillOpacity))",
            "Row \(format(tokens.color.rowFillOpacity))",
            "Field \(format(tokens.color.fieldFillOpacity))",
            "Field Border \(format(tokens.color.fieldBorderOpacity))"
        ]
    }

    static func motionCues(tokens: FFDesignTokens) -> [String] {
        [
            "Popover \(format(tokens.motion.popoverResponse)) / \(format(tokens.motion.popoverDamping))",
            "Section \(format(tokens.motion.sectionResponse)) / \(format(tokens.motion.sectionDamping))",
            "Control \(format(tokens.motion.controlResponse)) / \(format(tokens.motion.controlDamping))",
            "Breathing \(format(tokens.motion.breathingDuration))"
        ]
    }

    static func ringCues(tokens: FFDesignTokens) -> [String] {
        [
            "Size \(format(tokens.ring.size))",
            "Stroke \(format(tokens.ring.strokeWidth))",
            "Timer \(format(tokens.ring.timerFontSize)) \(tokens.ring.timerFontWeight.rawValue)",
            "Label \(format(tokens.ring.labelFontSize)) \(tokens.ring.labelFontWeight.rawValue)",
            "Tracking \(format(tokens.ring.digitTracking)) / \(format(tokens.ring.labelTracking))",
            "Glow \(format(tokens.ring.glowRadius)) / \(format(tokens.ring.glowOpacity))",
            "Disc \(format(tokens.ring.backgroundDiscOpacity))",
            "Track \(format(tokens.ring.trackOpacity))"
        ]
    }

    private static func format<T: BinaryFloatingPoint>(_ value: T) -> String {
        if Double(value).rounded() == Double(value) {
            return String(format: "%.0f", Double(value))
        }
        return String(format: "%.1f", Double(value))
    }
}

enum DesignLabButtonChromeShape: String, Codable, Equatable {
    case capsule
}

struct DesignLabButtonChrome: Equatable {
    let shape: DesignLabButtonChromeShape
    let controlHeight: CGFloat
    let iconFrame: CGFloat
    let containerRadius: CGFloat
    let titleSize: CGFloat
    let subtitleSize: CGFloat
    let titleWeight: FFWeightToken
    let subtitleWeight: FFWeightToken
    let primaryTintOpacity: Double
    let secondaryTintOpacity: Double
    let badges: [String]
}
