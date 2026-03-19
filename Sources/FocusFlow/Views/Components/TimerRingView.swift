import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    private let ringSize: CGFloat = 178
    private let strokeWidth: CGFloat = 5
    private let discInset: CGFloat = 14

    var body: some View {
        ZStack {
            // Inner dark disc (recessed look)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            LiquidDesignTokens.Surface.containerLow,
                            LiquidDesignTokens.Surface.background
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: ringSize / 2 - discInset
                    )
                )
                .frame(width: ringSize - discInset * 2, height: ringSize - discInset * 2)

            // Track ring (subtle)
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: strokeWidth)

            // Specular highlight on track (top-left edge)
            Circle()
                .trim(from: 0.62, to: 0.88)
                .stroke(Color.white.opacity(0.08), lineWidth: strokeWidth)
                .rotationEffect(.degrees(0))

            // Progress ring with gradient
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringGlowColor.opacity(0.4), radius: 12)
                .shadow(color: ringGlowColor.opacity(0.2), radius: 24)
                .animation(.easeInOut(duration: 0.75), value: progress)

            // Center text
            VStack(spacing: 4) {
                Text(timeString)
                    .font(LiquidDesignTokens.Typography.displayLarge)
                    .monospacedDigit()
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .contentTransition(.numericText(countsDown: true))

                TrackedLabel(
                    text: label,
                    font: LiquidDesignTokens.Typography.labelSmall,
                    color: labelColor,
                    tracking: 2.0
                )
            }
            .padding(.horizontal, 10)
        }
        .frame(width: ringSize, height: ringSize)
    }

    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: [
                ringColor.opacity(0.3),
                ringColor,
                ringColor.opacity(0.8),
                ringColor
            ],
            center: .center
        )
    }

    private var ringColor: Color {
        switch state {
        case .focusing:
            LiquidDesignTokens.Spectral.primaryContainer
        case .paused:
            LiquidDesignTokens.Spectral.amberDark
        case .onBreak(let type):
            type == .longBreak ? .purple : LiquidDesignTokens.Spectral.mintDark
        case .idle:
            Color.white.opacity(0.15)
        }
    }

    private var ringGlowColor: Color {
        switch state {
        case .focusing:
            LiquidDesignTokens.Spectral.electricBlue
        case .paused:
            LiquidDesignTokens.Spectral.amber
        case .onBreak:
            LiquidDesignTokens.Spectral.mint
        case .idle:
            .clear
        }
    }

    private var labelColor: Color {
        switch state {
        case .focusing:
            LiquidDesignTokens.Surface.onSurfaceMuted
        case .paused:
            LiquidDesignTokens.Spectral.amber
        case .onBreak:
            LiquidDesignTokens.Spectral.mint
        case .idle:
            LiquidDesignTokens.Surface.onSurfaceMuted
        }
    }
}
