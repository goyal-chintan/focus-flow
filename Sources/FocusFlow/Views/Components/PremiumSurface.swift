import SwiftUI

struct PremiumSurface<Content: View>: View {
    enum Style {
        case hero
        case card
        case inset

        var padding: CGFloat {
            switch self {
            case .hero: FFSpacing.xl
            case .card: FFSpacing.lg
            case .inset: FFSpacing.md
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .hero: FFRadius.hero
            case .card: FFRadius.card
            case .inset: FFRadius.control
            }
        }

        var fill: Color {
            switch self {
            case .hero: FFColor.panelHighlight
            case .card: FFColor.panelHighlight
            case .inset: FFColor.insetFill
            }
        }
    }

    let style: Style
    let alignment: HorizontalAlignment
    let content: Content

    init(
        style: Style = .card,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: FFSpacing.md) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(style.padding)
        .background(style.fill, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .ffCardChrome(cornerRadius: style.cornerRadius)
    }
}
