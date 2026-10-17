import SwiftUI

/// Shared duration preset pill row used across popover, manual session, and session edit views.
struct DurationPresetRow: View {
    let presets: [Int]
    @Binding var selectedMinutes: Int
    var showCustom: Bool = false
    @Binding var isCustomActive: Bool

    var minHeight: CGFloat = 30

    init(
        presets: [Int],
        selectedMinutes: Binding<Int>,
        showCustom: Bool = false,
        isCustomActive: Binding<Bool> = .constant(false),
        minHeight: CGFloat = 30
    ) {
        self.presets = presets
        self._selectedMinutes = selectedMinutes
        self.showCustom = showCustom
        self._isCustomActive = isCustomActive
        self.minHeight = minHeight
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { mins in
                    presetPill(mins)
                }

                if showCustom {
                    customPill
                }
            }
        }
    }

    private func presetPill(_ mins: Int) -> some View {
        let isSelected = !isCustomActive && selectedMinutes == mins
        return Button {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.control) { selectedMinutes = mins }
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) { isCustomActive = false }
        } label: {
            Text("\(mins)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonBorderShape(.capsule)
        .if(isSelected) { view in
            view.buttonStyle(.glassProminent)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
        }
        .if(!isSelected) { view in
            view.buttonStyle(.glass)
        }
        .accessibilityLabel("\(mins) minutes")
    }

    private var customPill: some View {
        Button {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) { isCustomActive = true }
        } label: {
            Text("Custom")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonBorderShape(.capsule)
        .if(isCustomActive) { view in
            view.buttonStyle(.glassProminent)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
        }
        .if(!isCustomActive) { view in
            view.buttonStyle(.glass)
        }
        .accessibilityLabel("Custom duration")
    }
}
