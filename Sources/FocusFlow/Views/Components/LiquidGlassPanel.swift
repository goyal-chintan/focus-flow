import SwiftUI

struct LiquidGlassPanel<Content: View>: View {
    @Environment(\.focusFlowEvidenceRendering) private var isEvidenceRendering
    let cornerRadius: CGFloat
    private let content: Content

    init(
        cornerRadius: CGFloat = LiquidDesignTokens.CornerRadius.panel,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if isEvidenceRendering {
            content
                .obsidianGlass(cornerRadius: cornerRadius)
        } else {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
