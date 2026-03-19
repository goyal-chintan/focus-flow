import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    private let ringSize: CGFloat = 178
    private let strokeWidth: CGFloat = 8
    private let discInset: CGFloat = 16

    @State private var glowPulse: Bool = false
    @State private var breatheScale: CGFloat = 1.0
    @State private var breatheOpacity: Double = 1.0
    @State private var specularRotation: Double = 0

    private var isActive: Bool {
        switch state {
        case .focusing, .paused, .onBreak: true
        case .idle: false
        }
    }

    var body: some View {
        ZStack {
            // Inner disc — breathing when active
            Circle()
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: Circle())
                .frame(width: ringSize - discInset * 2, height: ringSize - discInset * 2)
                .clipShape(Circle())
                .scaleEffect(breatheScale)
                .opacity(breatheOpacity)

            // Track ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: strokeWidth)

            // Rotating specular highlight on track
            Circle()
                .trim(from: 0.62, to: 0.88)
                .stroke(Color.white.opacity(0.12), lineWidth: strokeWidth)
                .rotationEffect(.degrees(specularRotation))

            // Remaining ring — shows what's left
            if isActive && progress < 1.0 {
                Circle()
                    .trim(from: max(0.001, progress), to: 1.0)
                    .stroke(
                        ringColor.opacity(0.25),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(FFMotion.progress, value: progress)
            }

            // Progress ring — fills as time elapses
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringGlowColor.opacity(glowPulse ? 0.6 : 0.3), radius: glowPulse ? 18 : 10)
                .shadow(color: ringGlowColor.opacity(glowPulse ? 0.35 : 0.12), radius: glowPulse ? 30 : 20)
                .animation(FFMotion.progress, value: progress)

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
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                // Breathing disc animation
                withAnimation(FFMotion.breathing) {
                    breatheScale = 1.03
                    breatheOpacity = 0.85
                }
                // Glow pulse
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
                // Slow specular rotation
                withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                    specularRotation = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    glowPulse = false
                    breatheScale = 1.0
                    breatheOpacity = 1.0
                    specularRotation = 0
                }
            }
        }
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
