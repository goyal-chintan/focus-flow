import SwiftUI

struct ColorLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFColorTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabSectionHeader(title: "Color Tokens (FFColor)") {
                    store.pushUndo(tokens); tokens.color = FFColorTokens()
                }

                TokenColorPicker(label: "focus", selection: $tokens.color.focusToken)
                TokenColorPicker(label: "success", selection: $tokens.color.successToken)
                TokenColorPicker(label: "warning", selection: $tokens.color.warningToken)
                TokenColorPicker(label: "danger", selection: $tokens.color.dangerToken)
                TokenColorPicker(label: "deepFocus", selection: $tokens.color.deepFocusToken)

                Divider()
                Text("Panel & Surface Opacities").font(.subheadline.bold())
                TokenSlider(label: "panelFillOpacity", value: $tokens.color.panelFillOpacity, range: 0...1, step: 0.01, defaultValue: d.panelFillOpacity) { store.pushUndo(tokens) }
                TokenSlider(label: "panelBorderOpacity", value: $tokens.color.panelBorderOpacity, range: 0...1, step: 0.01, defaultValue: d.panelBorderOpacity) { store.pushUndo(tokens) }
                TokenSlider(label: "panelHighlightOpacity", value: $tokens.color.panelHighlightOpacity, range: 0...1, step: 0.01, defaultValue: d.panelHighlightOpacity) { store.pushUndo(tokens) }
                TokenSlider(label: "insetFillOpacity", value: $tokens.color.insetFillOpacity, range: 0...1, step: 0.01, defaultValue: d.insetFillOpacity) { store.pushUndo(tokens) }
                TokenSlider(label: "rowFillOpacity", value: $tokens.color.rowFillOpacity, range: 0...1, step: 0.01, defaultValue: d.rowFillOpacity) { store.pushUndo(tokens) }
                TokenSlider(label: "fieldFillOpacity", value: $tokens.color.fieldFillOpacity, range: 0...1, step: 0.01, defaultValue: d.fieldFillOpacity) { store.pushUndo(tokens) }
                TokenSlider(label: "fieldBorderOpacity", value: $tokens.color.fieldBorderOpacity, range: 0...1, step: 0.01, defaultValue: d.fieldBorderOpacity) { store.pushUndo(tokens) }

                HStack(spacing: 12) {
                    colorSwatch("Focus", color: tokens.color.focus)
                    colorSwatch("Success", color: tokens.color.success)
                    colorSwatch("Warning", color: tokens.color.warning)
                    colorSwatch("Danger", color: tokens.color.danger)
                    colorSwatch("Deep", color: tokens.color.deepFocus)
                }.padding(.top, 8)
            }.padding()
        }
    }

    private func colorSwatch(_ label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 40, height: 30)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
