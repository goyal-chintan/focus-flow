import SwiftUI

/// Pre-session card shown in idle state when coach is enabled.
/// Helps the user set a quick mental checkpoint before starting: what type of work
/// and how much they're dreading it. This powers personalized coaching.
struct FocusCoachPreSessionCard: View {
    @Binding var selectedTaskType: FocusCoachTaskType
    @Binding var resistanceLevel: Int

    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            // Header row
            Button(action: { withAnimation(FFMotion.section) { isExpanded.toggle() } }) {
                HStack(spacing: LiquidDesignTokens.Spacing.small) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)

                    Text("Quick Check-in")
                        .font(LiquidDesignTokens.Typography.labelMedium)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                    Spacer()

                    // Collapsed summary
                    if !isExpanded {
                        HStack(spacing: 3) {
                            Text(selectedTaskType.displayName)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                            Text("·")
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                            Text(resistanceLabel)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(resistanceColor)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(LiquidDesignTokens.Spacing.medium)
        .background {
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.card)
                .fill(LiquidDesignTokens.Spectral.electricBlue.opacity(isHovered ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.card)
                        .strokeBorder(LiquidDesignTokens.Spectral.electricBlue.opacity(0.1), lineWidth: 0.5)
                )
        }
        .onHover { hovering in
            withAnimation(FFMotion.control) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick check-in before focus")
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            // Task type picker
            VStack(alignment: .leading, spacing: 4) {
                Text("What kind of work?")
                    .font(LiquidDesignTokens.Typography.labelSmall)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

                HStack(spacing: LiquidDesignTokens.Spacing.xSmall) {
                    ForEach(FocusCoachTaskType.allCases, id: \.rawValue) { type in
                        taskTypeChip(type)
                    }
                }
            }

            // Resistance — with clear human explanation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("How much are you dreading this?")
                        .font(LiquidDesignTokens.Typography.labelSmall)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

                    Spacer()

                    Text(resistanceLabel)
                        .font(LiquidDesignTokens.Typography.labelSmall)
                        .foregroundStyle(resistanceColor)
                }

                // Discrete resistance dots (1-5)
                HStack(spacing: LiquidDesignTokens.Spacing.small) {
                    ForEach(1...5, id: \.self) { level in
                        Circle()
                            .fill(level <= resistanceLevel ? resistanceColor : Color.white.opacity(0.08))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        level <= resistanceLevel ? resistanceColor.opacity(0.5) : Color.white.opacity(0.06),
                                        lineWidth: 0.5
                                    )
                            )
                            .onTapGesture {
                                withAnimation(FFMotion.control) {
                                    resistanceLevel = level
                                }
                            }
                            .accessibilityLabel("Level \(level)")
                            .accessibilityAddTraits(level == resistanceLevel ? .isSelected : [])
                    }
                }

                Text("High resistance = gentler coaching pace")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.6))
                    .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func taskTypeChip(_ type: FocusCoachTaskType) -> some View {
        let isSelected = selectedTaskType == type

        Button(action: {
            withAnimation(FFMotion.control) {
                selectedTaskType = type
            }
        }) {
            Text(type.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected
                    ? LiquidDesignTokens.Spectral.electricBlue
                    : LiquidDesignTokens.Surface.onSurfaceMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(isSelected
                            ? LiquidDesignTokens.Spectral.electricBlue.opacity(0.12)
                            : Color.white.opacity(0.04))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected
                                        ? LiquidDesignTokens.Spectral.electricBlue.opacity(0.3)
                                        : Color.white.opacity(0.06),
                                    lineWidth: 0.5
                                )
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var resistanceLabel: String {
        switch resistanceLevel {
        case 1: "Easy"
        case 2: "Manageable"
        case 3: "Some effort"
        case 4: "Tough"
        default: "Dreading it"
        }
    }

    private var resistanceColor: Color {
        switch resistanceLevel {
        case 1, 2: LiquidDesignTokens.Spectral.mint
        case 3: LiquidDesignTokens.Spectral.amber
        default: LiquidDesignTokens.Spectral.salmon
        }
    }
}
