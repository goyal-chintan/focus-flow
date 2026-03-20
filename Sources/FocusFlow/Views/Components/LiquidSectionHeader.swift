import SwiftUI

struct LiquidSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidDesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.xSmall) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))

                if let subtitle {
                    Text(subtitle)
                        .font(LiquidDesignTokens.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: LiquidDesignTokens.Spacing.small)
            trailing
        }
    }
}

extension LiquidSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}
