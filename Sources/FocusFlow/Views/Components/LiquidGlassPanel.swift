import SwiftUI

struct LiquidGlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    private let content: Content

    init(
        cornerRadius: CGFloat = LiquidDesignTokens.CornerRadius.panel,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
