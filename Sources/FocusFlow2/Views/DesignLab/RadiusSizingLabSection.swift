import SwiftUI

struct RadiusLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFRadiusTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabSectionHeader(title: "Radius Tokens (FFRadius)") {
                    store.pushUndo(tokens); tokens.radius = FFRadiusTokens()
                }
                TokenSlider(label: "control", value: $tokens.radius.control, range: 0...40, step: 1, defaultValue: d.control) { store.pushUndo(tokens) }
                TokenSlider(label: "card", value: $tokens.radius.card, range: 0...40, step: 1, defaultValue: d.card) { store.pushUndo(tokens) }
                TokenSlider(label: "hero", value: $tokens.radius.hero, range: 0...40, step: 1, defaultValue: d.hero) { store.pushUndo(tokens) }

                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: tokens.radius.control).fill(.blue.opacity(0.2)).frame(width: 60, height: 40).overlay(Text("Control").font(.caption2))
                    RoundedRectangle(cornerRadius: tokens.radius.card).fill(.blue.opacity(0.2)).frame(width: 60, height: 40).overlay(Text("Card").font(.caption2))
                    RoundedRectangle(cornerRadius: tokens.radius.hero).fill(.blue.opacity(0.2)).frame(width: 60, height: 40).overlay(Text("Hero").font(.caption2))
                }
                .padding(.top, 8)
            }.padding()
        }
    }
}

struct SizingLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFSizeTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabSectionHeader(title: "Size Tokens (FFSize)") {
                    store.pushUndo(tokens); tokens.sizing = FFSizeTokens()
                }
                TokenSlider(label: "controlMin", value: $tokens.sizing.controlMin, range: 20...80, step: 1, defaultValue: d.controlMin) { store.pushUndo(tokens) }
                TokenSlider(label: "iconFrame", value: $tokens.sizing.iconFrame, range: 20...80, step: 1, defaultValue: d.iconFrame) { store.pushUndo(tokens) }
                TokenSlider(label: "heroIcon", value: $tokens.sizing.heroIcon, range: 30...120, step: 1, defaultValue: d.heroIcon) { store.pushUndo(tokens) }
            }.padding()
        }
    }
}
