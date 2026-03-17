import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        PremiumSurface(style: .card, alignment: .leading) {
            HStack(alignment: .top, spacing: FFSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                        .fill(color.opacity(0.14))

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text(title)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(FFType.cardValue)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: FFSpacing.sm)
            }
        }
    }
}
