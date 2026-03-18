import SwiftUI

struct RingLabSection: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store

    var body: some View {
        @Bindable var tokens = tokens
        let d = FFRingTokens()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabSectionHeader(title: "Timer Ring Tokens") {
                    store.pushUndo(tokens); tokens.ring = FFRingTokens()
                }

                ringGeometry(tokens: $tokens, d: d)
                Divider()
                ringTypography(tokens: $tokens, d: d)
                Divider()
                ringEffects(tokens: $tokens, d: d)
                Divider()
                ringPreview
            }.padding()
        }
    }

    private func ringGeometry(tokens: Bindable<FFDesignTokens>, d: FFRingTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Geometry").font(.subheadline.bold())
            TokenSlider(label: "size", value: tokens.ring.size, range: 80...400, step: 1, defaultValue: d.size) { store.pushUndo(self.tokens) }
            TokenSlider(label: "strokeWidth", value: tokens.ring.strokeWidth, range: 1...20, step: 0.1, defaultValue: d.strokeWidth) { store.pushUndo(self.tokens) }
        }
    }

    private func ringTypography(tokens: Bindable<FFDesignTokens>, d: FFRingTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Typography").font(.subheadline.bold())
            TokenSlider(label: "timerFontSize", value: tokens.ring.timerFontSize, range: 20...120, step: 0.5, defaultValue: d.timerFontSize) { store.pushUndo(self.tokens) }
            TokenPicker(label: "timerFontWeight", selection: tokens.ring.timerFontWeight)
            TokenSlider(label: "digitTracking", value: tokens.ring.digitTracking, range: 0...10, step: 0.1, defaultValue: d.digitTracking) { store.pushUndo(self.tokens) }
            TokenSlider(label: "labelFontSize", value: tokens.ring.labelFontSize, range: 8...30, step: 0.5, defaultValue: d.labelFontSize) { store.pushUndo(self.tokens) }
            TokenPicker(label: "labelFontWeight", selection: tokens.ring.labelFontWeight)
            TokenSlider(label: "labelTracking", value: tokens.ring.labelTracking, range: 0...10, step: 0.1, defaultValue: d.labelTracking) { store.pushUndo(self.tokens) }
        }
    }

    private func ringEffects(tokens: Bindable<FFDesignTokens>, d: FFRingTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Effects").font(.subheadline.bold())
            TokenSlider(label: "backgroundDiscOpacity", value: tokens.ring.backgroundDiscOpacity, range: 0...1, step: 0.01, defaultValue: d.backgroundDiscOpacity) { store.pushUndo(self.tokens) }
            TokenSlider(label: "trackOpacity", value: tokens.ring.trackOpacity, range: 0...1, step: 0.01, defaultValue: d.trackOpacity) { store.pushUndo(self.tokens) }
            TokenSlider(label: "glowRadius", value: tokens.ring.glowRadius, range: 0...30, step: 0.5, defaultValue: d.glowRadius) { store.pushUndo(self.tokens) }
            TokenSlider(label: "glowOpacity", value: tokens.ring.glowOpacity, range: 0...1, step: 0.01, defaultValue: d.glowOpacity) { store.pushUndo(self.tokens) }
        }
    }

    private var ringPreview: some View {
        VStack(spacing: 8) {
            Text("Preview").font(.caption).foregroundStyle(.secondary)
            let r = tokens.ring
            ZStack {
                Circle().fill(Color.primary.opacity(r.backgroundDiscOpacity))
                Circle().stroke(Color.primary.opacity(r.trackOpacity), lineWidth: r.strokeWidth)
                Circle().trim(from: 0, to: 0.65)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: r.strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.blue.opacity(r.glowOpacity), radius: r.glowRadius)
                VStack(spacing: tokens.spacing.xs) {
                    Text("12:41").font(r.timerFont).monospacedDigit().tracking(r.digitTracking)
                    Text("FOCUSING").font(r.labelFont).foregroundStyle(.secondary).tracking(r.labelTracking)
                }
            }
            .frame(width: min(r.size * 0.6, 200), height: min(r.size * 0.6, 200))
        }
    }
}
