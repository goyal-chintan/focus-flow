import SwiftUI

enum LiquidDesignTokens {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum CornerRadius {
        static let input: CGFloat = 6
        static let control: CGFloat = 8
        static let picker: CGFloat = 10
        static let metricCard: CGFloat = 14
        static let panel: CGFloat = 16
    }

    enum Padding {
        static let controlVertical: CGFloat = 10
        static let metricCardVertical: CGFloat = 16
    }

    enum Typography {
        static let controlLabel = Font.system(size: 13, weight: .semibold)
        static let metricValue = Font.system(.title2, weight: .semibold)
        static let metricLabel = Font.caption2
        static let icon = Font.title3
        static let sectionTitle = Font.headline
        static let sectionSubtitle = Font.subheadline
    }

    enum Tint {
        static let primary: Color = .blue
        static let destructive: Color = .red
    }
}
