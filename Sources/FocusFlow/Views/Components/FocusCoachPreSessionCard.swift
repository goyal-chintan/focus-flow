import SwiftUI

/// Pre-session card shown in idle state when coach is enabled.
/// Encourages task declaration with resistance rating and suggested duration.
/// Follows MCII (Mental Contrasting with Implementation Intentions) research.
struct FocusCoachPreSessionCard: View {
    @Binding var taskTitle: String
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

                    Text("Set Your Intention")
                        .font(LiquidDesignTokens.Typography.labelMedium)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !taskTitle.isEmpty {
                // Collapsed summary
                Text(taskTitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .lineLimit(1)
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
        .accessibilityLabel("Set your focus intention")
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            // Task title input
            TextField("What are you working on?", text: $taskTitle)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .textFieldStyle(.plain)
                .padding(.horizontal, LiquidDesignTokens.Spacing.medium)
                .padding(.vertical, LiquidDesignTokens.Spacing.small)
                .background {
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                }
                .accessibilityLabel("Task description")

            // Task type picker
            HStack(spacing: LiquidDesignTokens.Spacing.xSmall) {
                ForEach(FocusCoachTaskType.allCases, id: \.rawValue) { type in
                    taskTypeChip(type)
                }
            }

            // Resistance slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Expected Resistance")
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
                            .accessibilityLabel("Resistance level \(level)")
                            .accessibilityAddTraits(level == resistanceLevel ? .isSelected : [])
                    }
                }
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
                .font(LiquidDesignTokens.Typography.labelSmall)
                .foregroundStyle(isSelected
                    ? LiquidDesignTokens.Spectral.electricBlue
                    : LiquidDesignTokens.Surface.onSurfaceMuted)
                .padding(.horizontal, LiquidDesignTokens.Spacing.small)
                .padding(.vertical, 4)
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
        case 1: "Very Low"
        case 2: "Low"
        case 3: "Medium"
        case 4: "High"
        default: "Very High"
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
