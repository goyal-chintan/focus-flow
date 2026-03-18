import SwiftUI

struct TypographyLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFTypographyTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabSectionHeader(title: "Typography Tokens (FFType)") {
                    store.pushUndo(tokens); tokens.typography = FFTypographyTokens()
                }

                fontRow("heroLabel", size: $tokens.typography.heroLabelSize, weight: $tokens.typography.heroLabelWeight, dSize: d.heroLabelSize, dWeight: d.heroLabelWeight, preview: tokens.typography.heroLabel)
                fontRow("title", size: $tokens.typography.titleSize, weight: $tokens.typography.titleWeight, dSize: d.titleSize, dWeight: d.titleWeight, preview: tokens.typography.title)
                fontRow("titleLarge", size: $tokens.typography.titleLargeSize, weight: $tokens.typography.titleLargeWeight, dSize: d.titleLargeSize, dWeight: d.titleLargeWeight, preview: tokens.typography.titleLarge)
                fontRow("cardValue", size: $tokens.typography.cardValueSize, weight: $tokens.typography.cardValueWeight, dSize: d.cardValueSize, dWeight: d.cardValueWeight, preview: tokens.typography.cardValue)
                fontRow("body", size: $tokens.typography.bodySize, weight: $tokens.typography.bodyWeight, dSize: d.bodySize, dWeight: d.bodyWeight, preview: tokens.typography.bodyFont)
                fontRow("callout", size: $tokens.typography.calloutSize, weight: $tokens.typography.calloutWeight, dSize: d.calloutSize, dWeight: d.calloutWeight, preview: tokens.typography.callout)
                fontRow("meta", size: $tokens.typography.metaSize, weight: $tokens.typography.metaWeight, dSize: d.metaSize, dWeight: d.metaWeight, preview: tokens.typography.meta)
                fontRow("micro", size: $tokens.typography.microSize, weight: $tokens.typography.microWeight, dSize: d.microSize, dWeight: d.microWeight, preview: tokens.typography.micro)
            }.padding()
        }
    }

    private func fontRow(_ label: String, size: Binding<CGFloat>, weight: Binding<FFWeightToken>, dSize: CGFloat, dWeight: FFWeightToken, preview: Font) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(.body, design: .monospaced).bold())
            TokenSlider(label: "  size", value: size, range: 8...40, step: 0.5, defaultValue: dSize) { store.pushUndo(tokens) }
            TokenPicker(label: "  weight", selection: weight)
            Text("The quick brown fox").font(preview).padding(.leading, 188)
            Divider()
        }
    }
}
