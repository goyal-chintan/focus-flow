import SwiftUI

struct MotionLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFMotionTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabSectionHeader(title: "Motion Tokens (FFMotion)") {
                    store.pushUndo(tokens); tokens.motion = FFMotionTokens()
                }

                springEditor("popover", response: $tokens.motion.popoverResponse, damping: $tokens.motion.popoverDamping, dResponse: d.popoverResponse, dDamping: d.popoverDamping)
                springEditor("section", response: $tokens.motion.sectionResponse, damping: $tokens.motion.sectionDamping, dResponse: d.sectionResponse, dDamping: d.sectionDamping)
                springEditor("control", response: $tokens.motion.controlResponse, damping: $tokens.motion.controlDamping, dResponse: d.controlResponse, dDamping: d.controlDamping)

                Divider()
                TokenSlider(label: "breathingDuration", value: $tokens.motion.breathingDuration, range: 0.5...5.0, step: 0.1, defaultValue: d.breathingDuration) { store.pushUndo(tokens) }
            }.padding()
        }
    }

    private func springEditor(_ label: String, response: Binding<CGFloat>, damping: Binding<CGFloat>, dResponse: CGFloat, dDamping: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(.body, design: .monospaced).bold())
            TokenSlider(label: "  response", value: response, range: 0.05...3.0, step: 0.02, defaultValue: dResponse) { store.pushUndo(tokens) }
            TokenSlider(label: "  damping", value: damping, range: 0.1...1.5, step: 0.02, defaultValue: dDamping) { store.pushUndo(tokens) }
            TokenSpringPreview(response: response.wrappedValue, damping: damping.wrappedValue)
        }
    }
}
