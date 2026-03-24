import SwiftUI

/// Pre-session card shown in idle state when coach is enabled.
/// Helps the user set a quick mental checkpoint before starting: what type of work
/// and how much they're dreading it. This powers personalized coaching.
struct FocusCoachPreSessionCard: View {
    @Binding var selectedTaskType: FocusCoachTaskType
    @Binding var resistanceLevel: Int

    @State private var isExpanded = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effortBinding: Binding<Double> {
        Binding(
            get: { Double(resistanceLevel) },
            set: { newValue in
                withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.control) {
                    resistanceLevel = Int(newValue.rounded())
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            // Header row
            Button(action: { withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) { isExpanded.toggle() } }) {
                HStack(spacing: LiquidDesignTokens.Spacing.small) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                        .accessibilityHidden(true)

                    Text("Quick Check-in")
                        .font(LiquidDesignTokens.Typography.labelMedium)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                    Spacer()

                    // Collapsed summary
                    if !isExpanded {
                        HStack(spacing: 4) {
                            Text(selectedTaskType.displayName)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("·")
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                            Text(resistanceLabel)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(resistanceColor)
                                .lineLimit(1)
                        }
                        .layoutPriority(1)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if isExpanded {
                expandedContent
                    .transition(.opacity)
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
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.control) {
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

            // Effort slider (spec §2 calls for Easy/Normal/Hard chips, but a 1-5 slider
            // provides finer granularity and better hit-target ergonomics per HIG.
            // Intentional deviation — approved by user as preferred input modality.)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mental effort")
                        .font(LiquidDesignTokens.Typography.labelSmall)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

                    Spacer()

                    Text(resistanceLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(resistanceColor)
                        .monospacedDigit()
                }

                Slider(value: effortBinding, in: 1...5, step: 1)
                    .tint(resistanceColor)
                    .accessibilityLabel("Mental effort")
                    .accessibilityValue(resistanceLabel)

                HStack {
                    Text("Low")
                    Spacer()
                    Text("High")
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.75))

                Text("Higher effort tells coach to use a gentler ramp-up.")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func taskTypeChip(_ type: FocusCoachTaskType) -> some View {
        let isSelected = selectedTaskType == type

        Button(action: {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.control) {
                selectedTaskType = type
            }
        }) {
            Text(type.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(isSelected
                    ? LiquidDesignTokens.Spectral.electricBlue
                    : LiquidDesignTokens.Surface.onSurfaceMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
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
        case 1: "Low"
        case 2: "Light"
        case 3: "Moderate"
        case 4: "High"
        default: "Very high"
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
