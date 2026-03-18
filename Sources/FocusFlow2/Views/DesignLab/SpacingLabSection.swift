import SwiftUI

struct SpacingLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFSpacingTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabSectionHeader(title: "Spacing Tokens (FFSpacing)") {
                    store.pushUndo(tokens); tokens.spacing = FFSpacingTokens()
                }
                TokenSlider(label: "xxs", value: $tokens.spacing.xxs, range: 0...64, step: 1, defaultValue: d.xxs) { store.pushUndo(tokens) }
                TokenSlider(label: "xs", value: $tokens.spacing.xs, range: 0...64, step: 1, defaultValue: d.xs) { store.pushUndo(tokens) }
                TokenSlider(label: "sm", value: $tokens.spacing.sm, range: 0...64, step: 1, defaultValue: d.sm) { store.pushUndo(tokens) }
                TokenSlider(label: "md", value: $tokens.spacing.md, range: 0...64, step: 1, defaultValue: d.md) { store.pushUndo(tokens) }
                TokenSlider(label: "lg", value: $tokens.spacing.lg, range: 0...64, step: 1, defaultValue: d.lg) { store.pushUndo(tokens) }
                TokenSlider(label: "xl", value: $tokens.spacing.xl, range: 0...64, step: 1, defaultValue: d.xl) { store.pushUndo(tokens) }

                HStack(spacing: tokens.spacing.md) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(.blue.opacity(0.3)).frame(width: 40, height: 30)
                    }
                }
                .padding(.top, 8)
                Text("Preview: md spacing (\(Int(tokens.spacing.md))pt)").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
    }
}
