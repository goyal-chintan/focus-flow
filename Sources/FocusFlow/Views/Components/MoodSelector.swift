import SwiftUI

struct MoodSelector: View {
    @Binding var selectedMood: FocusMood?
    var style: Style = .compact

    enum Style {
        /// For companion window views (ManualSession, SessionEdit)
        case compact
        /// For standalone windows (SessionComplete)
        case regular

        var iconSize: CGFloat {
            switch self {
            case .compact: 14
            case .regular: 20
            }
        }

        var labelFont: Font {
            switch self {
            case .compact: .system(size: 10)
            case .regular: .system(size: 10, weight: .medium)
            }
        }

        var labelSpacing: CGFloat {
            switch self {
            case .compact: 2
            case .regular: 4
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact: 6
            case .regular: 12
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .compact: 12
            case .regular: 14
            }
        }

        var hSpacing: CGFloat {
            switch self {
            case .compact: 6
            case .regular: 8
            }
        }
    }

    var body: some View {
        HStack(spacing: style.hSpacing) {
            ForEach(FocusMood.allCases, id: \.self) { mood in
                moodButton(for: mood)
            }
        }
    }

    @ViewBuilder
    private func moodButton(for mood: FocusMood) -> some View {
        let isSelected = selectedMood == mood
        return Button { isSelected ? (selectedMood = nil) : (selectedMood = mood) } label: {
            VStack(spacing: style.labelSpacing) {
                Image(systemName: mood.icon)
                    .font(.system(size: style.iconSize))
                Text(mood.rawValue)
                    .font(style.labelFont)
            }
            .foregroundStyle(isSelected ? mood.color : LiquidDesignTokens.Surface.onSurfaceMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, style.verticalPadding)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(isSelected ? mood.color.opacity(0.14) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? mood.color.opacity(0.35) : Color.white.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(FFMotion.control, value: isSelected)
        .accessibilityLabel(isSelected ? "\(mood.rawValue), selected" : mood.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
