import SwiftUI

struct LiquidMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        LiquidGlassPanel(cornerRadius: LiquidDesignTokens.CornerRadius.card) {
            VStack(spacing: LiquidDesignTokens.Spacing.small) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)

                Text(value)
                    .font(.system(.title2, weight: .semibold))
                    .contentTransition(.numericText())

                Text(title)
                    .font(LiquidDesignTokens.Typography.labelSmall)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}
