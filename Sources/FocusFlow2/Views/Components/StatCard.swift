import SwiftUI

struct StatCard: View {
    @Environment(FFDesignTokens.self) private var tokens
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        PremiumSurface(style: .card, alignment: .leading) {
            HStack(alignment: .top, spacing: tokens.spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: tokens.radius.control, style: .continuous)
                        .fill(color.opacity(0.14))

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: tokens.spacing.xs) {
                    Text(title)
                        .font(tokens.typography.meta)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(tokens.typography.cardValue)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: tokens.spacing.sm)
            }
        }
    }
}
