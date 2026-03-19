import SwiftUI

struct LiquidMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        LiquidGlassPanel(cornerRadius: LiquidDesignTokens.CornerRadius.metricCard) {
            VStack(spacing: LiquidDesignTokens.Spacing.small) {
                Image(systemName: icon)
                    .font(LiquidDesignTokens.Typography.icon)
                    .foregroundStyle(color)

                Text(value)
                    .font(LiquidDesignTokens.Typography.metricValue)
                    .contentTransition(.numericText())

                Text(title)
                    .font(LiquidDesignTokens.Typography.metricLabel)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidDesignTokens.Padding.metricCardVertical)
        }
    }
}
