import SwiftUI

/// Reason chip selection sheet — shown when the coach detects an anomaly.
/// Presents 7 reason options as tappable chips (1–2 taps to complete).
/// Includes optional snooze action in the same surface.
struct FocusCoachReasonChipSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let anomalyKind: FocusCoachInterruptionKind
    let onSelect: (FocusCoachReason) -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    @State private var selectedReason: FocusCoachReason?
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(LiquidDesignTokens.Typography.headlineMedium)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                    Text("This helps your coach learn what's a real interruption vs. avoidance.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip reason")
            }

            // Reason chips — grouped by type
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
                // SECTION: Legitimate
                VStack(alignment: .leading, spacing: 8) {
                    Text("Legitimate")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    FlowLayout(spacing: LiquidDesignTokens.Spacing.small) {
                        ForEach(FocusCoachReason.legitimateChips, id: \.rawValue) { reason in
                            reasonChip(reason)
                        }
                    }
                }

                // SECTION: Avoidant
                VStack(alignment: .leading, spacing: 8) {
                    Text("Avoidant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .padding(.horizontal, 4)

                    FlowLayout(spacing: LiquidDesignTokens.Spacing.small) {
                        ForEach(FocusCoachReason.avoidantChips, id: \.rawValue) { reason in
                            reasonChip(reason)
                        }
                    }
                }
            }

            // Actions
            HStack(spacing: LiquidDesignTokens.Spacing.medium) {
                // Snooze button
                Button(action: onSnooze) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Snooze Coach")
                            .font(LiquidDesignTokens.Typography.labelSmall)
                    }
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .padding(.horizontal, LiquidDesignTokens.Spacing.medium)
                    .padding(.vertical, LiquidDesignTokens.Spacing.small)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(0.04))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Submit (only if reason selected)
                if let reason = selectedReason {
                    Button(action: { onSelect(reason) }) {
                        Text("Done")
                            .font(LiquidDesignTokens.Typography.labelMedium)
                            .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                            .padding(.horizontal, LiquidDesignTokens.Spacing.large)
                            .padding(.vertical, LiquidDesignTokens.Spacing.small)
                            .background {
                                Capsule()
                                    .fill(LiquidDesignTokens.Spectral.electricBlue.opacity(0.12))
                                    .overlay(
                                        Capsule().strokeBorder(LiquidDesignTokens.Spectral.electricBlue.opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .padding(LiquidDesignTokens.Spacing.large)
        .background {
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.panel)
                .fill(LiquidDesignTokens.Surface.containerLow)
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.panel)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        }
        .opacity(appear ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (appear ? 0 : 12))
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.popover) {
                appear = true
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.01) : FFMotion.control, value: selectedReason)
    }

    @ViewBuilder
    private func reasonChip(_ reason: FocusCoachReason) -> some View {
        let isSelected = selectedReason == reason

        Button(action: {
            withAnimation(FFMotion.control) {
                selectedReason = reason
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: iconName(for: reason))
                    .font(.system(size: 10))
                Text(reason.displayName)
                    .font(LiquidDesignTokens.Typography.labelSmall)
            }
            .foregroundStyle(isSelected ? chipAccent(for: reason) : LiquidDesignTokens.Surface.onSurfaceMuted)
            .padding(.horizontal, LiquidDesignTokens.Spacing.medium)
            .padding(.vertical, LiquidDesignTokens.Spacing.small)
            .background {
                Capsule()
                    .fill(isSelected
                        ? chipAccent(for: reason).opacity(0.12)
                        : Color.white.opacity(0.04))
                    .overlay(
                        Capsule().strokeBorder(
                            isSelected ? chipAccent(for: reason).opacity(0.25) : Color.white.opacity(0.06),
                            lineWidth: 0.5
                        )
                    )
            }
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel(reason.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var headerTitle: String {
        switch anomalyKind {
        case .midSessionStop: "Why did you stop?"
        case .breakOverrun: "Break ran long — what happened?"
        case .drift: "You drifted — what's going on?"
        case .fakeStart: "Started but didn't focus — why?"
        case .missedStart: "Missed your planned start"
        case .projectSwitch: "Why are you switching?"
        }
    }

    private func iconName(for reason: FocusCoachReason) -> String {
        reason.icon
    }

    private func chipAccent(for reason: FocusCoachReason) -> Color {
        reason.isLegitimate
            ? LiquidDesignTokens.Spectral.electricBlue
            : LiquidDesignTokens.Spectral.amber
    }
}

/// Simple flow layout for wrapping chips horizontally
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
