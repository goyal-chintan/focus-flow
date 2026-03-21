import SwiftUI

/// Shared duration preset pill row used across popover, manual session, and session edit views.
struct DurationPresetRow: View {
    let presets: [Int]
    @Binding var selectedMinutes: Int
    var showCustom: Bool = false
    @Binding var isCustomActive: Bool

    init(
        presets: [Int],
        selectedMinutes: Binding<Int>,
        showCustom: Bool = false,
        isCustomActive: Binding<Bool> = .constant(false)
    ) {
        self.presets = presets
        self._selectedMinutes = selectedMinutes
        self.showCustom = showCustom
        self._isCustomActive = isCustomActive
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { mins in
                presetPill(mins)
            }

            if showCustom {
                customPill
            }
        }
    }

    private func presetPill(_ mins: Int) -> some View {
        let isSelected = !isCustomActive && selectedMinutes == mins
        return Button {
            withAnimation(FFMotion.control) {
                selectedMinutes = mins
            }
            withAnimation(FFMotion.section) {
                isCustomActive = false
            }
        } label: {
            Text("\(mins)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
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
            withAnimation(FFMotion.section) {
                isCustomActive = true
            }
        } label: {
            Text("CUST")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
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
