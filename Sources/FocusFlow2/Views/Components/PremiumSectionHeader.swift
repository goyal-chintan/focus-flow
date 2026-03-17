import SwiftUI

struct PremiumSectionHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(
        _ title: String,
        eyebrow: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: FFSpacing.md) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(FFType.micro)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                Text(title)
                    .font(FFType.title)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: FFSpacing.md)

            trailing
        }
    }
}

extension PremiumSectionHeader where Trailing == EmptyView {
    init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil) {
        self.init(title, eyebrow: eyebrow, subtitle: subtitle) { EmptyView() }
    }
}
