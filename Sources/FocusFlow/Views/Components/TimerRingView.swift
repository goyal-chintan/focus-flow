import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    private let ringSize: CGFloat = 190
    private let strokeWidth: CGFloat = 6

    @State private var glowPulse: Bool = false

    private var isActive: Bool {
        switch state {
        case .focusing, .paused, .onBreak: true
        case .idle: false
        }
    }

    var body: some View {
        ZStack {
            // Outer halo ring (premium watch bezel)
            Circle()
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                .frame(width: ringSize + 6, height: ringSize + 6)

            // Tick marks (watch-face aesthetic)
            tickMarks

            // Inner disc with shadow
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: ringSize, height: ringSize)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.clear, Color.black.opacity(0.3)],
                                center: .center,
                                startRadius: ringSize * 0.2,
                                endRadius: ringSize * 0.5
                            )
                        )
                )

            // Full circle track for all states
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: strokeWidth)

            if state == .idle {
                // Subtle highlight arc
                Circle()
                    .trim(from: 0.72, to: 0.97)
                    .stroke(
                        ringColor.opacity(0.55),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else if state == .paused {
                pausedRings
            } else {
                // Remaining ring
                if isActive && progress < 1.0 {
                    Circle()
                        .trim(from: max(0.001, progress), to: 1.0)
                        .stroke(
                            ringColor.opacity(0.2),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(FFMotion.progress, value: progress)
                }

                // Progress ring
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(
                        ringGradient,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .if(state == .focusing) { view in
                        view.shadow(color: ringGlowColor.opacity(glowPulse ? 0.58 : 0.22), radius: glowPulse ? 16 : 9)
                            .shadow(color: ringGlowColor.opacity(glowPulse ? 0.2 : 0.05), radius: glowPulse ? 24 : 16)
                    }
                    .animation(FFMotion.progress, value: progress)
            }

            // Center text
            VStack(spacing: 5) {
                Text(timeString)
                    .font(.system(size: 40, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timeTextColor)
                    .contentTransition(.numericText(countsDown: true))

                TrackedLabel(
                    text: label,
                    font: .system(size: 10, weight: .medium),
                    color: labelColor.opacity(0.65),
                    tracking: 2.2
                )
            }
            .padding(.horizontal, 8)
        }
        .frame(width: ringSize + 6, height: ringSize + 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(timeString)")
        .accessibilityValue(state == .idle ? "Ready" : "\(Int(progress * 100)) percent complete")
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                withAnimation(FFMotion.breathing) {
                    glowPulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    glowPulse = false
                }
            }
        }
    }

    private var timeTextColor: Color {
        switch state {
        case .idle: LiquidDesignTokens.Surface.onSurface.opacity(0.72)
        case .focusing: .white
        case .paused: LiquidDesignTokens.Spectral.amber
        case .onBreak: LiquidDesignTokens.Spectral.mint
        }
    }

    private var ringGradient: AngularGradient {
        switch state {
        case .focusing:
            AngularGradient(
                colors: [
                    Color(hex: 0x3A4F85),
                    Color(hex: 0x5B96F8),
                    Color(hex: 0x7DB4FF),
                    Color(hex: 0x5B96F8),
                    Color(hex: 0x3A4F85)
                ],
                center: .center
            )
        default:
            AngularGradient(
                colors: [
                    ringColor.opacity(0.18),
                    ringColor,
                    ringColor.opacity(0.72),
                    ringColor
                ],
                center: .center
            )
        }
    }

    private var tickMarks: some View {
        ForEach(0..<60, id: \.self) { tick in
            let isMajor = tick % 5 == 0
            let tickLength: CGFloat = isMajor ? 6 : 4
            let tickColor = Color.white.opacity(isMajor ? 0.12 : 0.06)

            Rectangle()
                .fill(tickColor)
                .frame(width: 1, height: tickLength)
                .offset(y: -(ringSize / 2) + tickLength / 2 - 1)
                .rotationEffect(.degrees(Double(tick) * 6))
        }
    }

    private var pausedRings: some View {
        ZStack {
            Circle()
                .trim(from: 0.06, to: 0.86)
                .stroke(
                    Color.white.opacity(0.84),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.white.opacity(0.2), radius: 7, y: 1)

            Circle()
                .trim(from: 0.84, to: 1.0)
                .stroke(
                    AngularGradient(
                        colors: [
                            LiquidDesignTokens.Spectral.amber.opacity(0.95),
                            LiquidDesignTokens.Spectral.amberDark.opacity(0.95)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: LiquidDesignTokens.Spectral.amber.opacity(0.5), radius: 9, y: 2)

            Circle()
                .trim(from: 0.84, to: 1.0)
                .stroke(
                    LiquidDesignTokens.Spectral.amber.opacity(0.35),
                    style: StrokeStyle(lineWidth: strokeWidth + 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 1.8)
        }
    }

    private var ringColor: Color {
        switch state {
        case .focusing:
            Color(hex: 0x506392)
        case .paused:
            LiquidDesignTokens.Spectral.amberDark
        case .onBreak(let type):
            type == .longBreak ? .purple : LiquidDesignTokens.Spectral.mintDark
        case .idle:
            Color(hex: 0x4C5A80)
        }
    }

    private var ringGlowColor: Color {
        switch state {
        case .focusing:
            Color(hex: 0x5B96F8)
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
