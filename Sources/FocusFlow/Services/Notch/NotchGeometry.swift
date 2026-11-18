import CoreGraphics

/// Where the notch companion sits (notch design: docs/plans/2026-10-28-notch-companion-design.md).
/// Pure: the controller feeds it `NSScreen` values; tests feed it numbers.
struct NotchGeometry: Equatable, Sendable {
    /// The hardware notch (or, without one, the virtual notch the pill hugs), in screen coordinates
    /// (origin bottom-left, like AppKit).
    let notch: CGRect
    let hasHardwareNotch: Bool

    /// Width of each "wing" beside the notch in the compact state.
    static let wingWidth: CGFloat = 74
    static let expandedSize = CGSize(width: 500, height: 330)
    /// A screen without a notch gets a virtual one this wide, on the top edge.
    static let virtualNotchWidth: CGFloat = 180

    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (0 without a notch).
    ///   - leftAreaWidth / rightAreaWidth: widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
    ///     (the menu bar on each side of the notch). Nil without a notch.
    ///   - menuBarHeight: used for the virtual notch.
    init(screenFrame: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?, menuBarHeight: CGFloat) {
        if safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth, screenFrame.width - left - right > 40 {
            let width = screenFrame.width - left - right
            notch = CGRect(x: screenFrame.minX + left, y: screenFrame.maxY - safeAreaTop, width: width, height: safeAreaTop)
            hasHardwareNotch = true
        } else {
            let height = max(22, menuBarHeight)
            notch = CGRect(
                x: screenFrame.midX - Self.virtualNotchWidth / 2,
                y: screenFrame.maxY - height,
                width: Self.virtualNotchWidth,
                height: height
            )
            hasHardwareNotch = false
        }
    }

    /// The compact island: the notch plus a wing on each side.
    var compactFrame: CGRect {
        notch.insetBy(dx: -Self.wingWidth, dy: 0)
    }

    /// The expanded island, hanging from the top edge, centred on the notch.
    var expandedFrame: CGRect {
        let size = CGSize(width: max(Self.expandedSize.width, notch.width + 2 * Self.wingWidth), height: Self.expandedSize.height + notch.height)
        return CGRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
    }
}
