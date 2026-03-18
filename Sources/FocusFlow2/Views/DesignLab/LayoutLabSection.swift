import SwiftUI

struct LayoutLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFLayoutTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabSectionHeader(title: "Layout Tokens") {
                    store.pushUndo(tokens); tokens.layout = FFLayoutTokens()
                }
                TokenSlider(label: "popoverWidth", value: $tokens.layout.popoverWidth, range: 250...500, step: 1, defaultValue: d.popoverWidth) { store.pushUndo(tokens) }
                TokenSlider(label: "sessionDotSize", value: $tokens.layout.sessionDotSize, range: 2...20, step: 1, defaultValue: d.sessionDotSize) { store.pushUndo(tokens) }
                TokenSlider(label: "barChartHeight", value: $tokens.layout.barChartHeight, range: 60...400, step: 1, defaultValue: d.barChartHeight) { store.pushUndo(tokens) }
            }.padding()
        }
    }
}
