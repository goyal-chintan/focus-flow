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

                Text(value)
                    .font(.system(.title2, weight: .semibold))
                    .contentTransition(.numericText())

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}
