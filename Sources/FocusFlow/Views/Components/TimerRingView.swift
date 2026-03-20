import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState
    let isOvertime: Bool
    var pauseDuration: TimeInterval = 0

    private let ringSize: CGFloat = 170
    private let strokeWidth: CGFloat = 6

    @State private var glowPulse: Bool = false

    private var isActive: Bool {
        switch state {
        case .focusing, .paused, .onBreak: true
        case .idle: false
        }
    }

    // MARK: - Outer Ring Computed Properties

    private var outerProgress: Double {
        guard isActive else { return 0 }
        return min(max(progress, 0), 1)
    }

    private var outerGlowColor: Color {
        switch state {
        case .paused:
            if pauseDuration > 300 { return .red }
            if pauseDuration > 180 { return Color(hex: 0xE6A820) }
            return ringGlowColor
        case .onBreak:
            if isOvertime {
                // Escalate: >1.0 progress means overtime; use progress magnitude for severity
                if progress > 1.5 { return .red }
                if progress > 1.0 { return Color(hex: 0xE6A820) }
            }
            return ringGlowColor
        default:
            return ringGlowColor
        }
    }

    private var outerGlowOpacity: Double {
        if progress >= 0.75 && isActive {
            // Lerp from 0.3 at 0.75 to 0.6 at 1.0
            let t = min((progress - 0.75) / 0.25, 1.0)
            return 0.3 + t * 0.3
        }
        return 0.3
    }

    private var outerGlowRadius: CGFloat {
        if progress >= 0.75 && isActive {
            let t = min((progress - 0.75) / 0.25, 1.0)
            return 4 + CGFloat(t) * 4
        }
        return 4
    }

    var body: some View {
        ZStack {
            // Outer halo — only visible when active (no gray track in idle)
            if isActive {
                outerHaloArc
            }

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

            // Main ring — state-dependent
            if state == .idle {
                // Idle: very subtle track only (no heavy gray)
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: strokeWidth)
            } else if state == .paused {
                pausedRings
            } else if isOvertime {
                overtimeRings
            } else {
                // Focusing / Break: progress arc only, no gray remaining
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(
                        ringGradient,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringGlowColor.opacity(glowPulse ? 0.65 : 0.28), radius: glowPulse ? 18 : 10)
                    .shadow(color: ringGlowColor.opacity(glowPulse ? 0.25 : 0.08), radius: glowPulse ? 28 : 18)
                    .animation(FFMotion.progress, value: progress)
            }

            // Center text
            VStack(spacing: 5) {
                Text(timeString)
                    .font(.system(size: 36, weight: .ultraLight, design: .rounded))
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

    // Paused: single amber arc showing how far timer reached, with breathing pulse
    private var pausedRings: some View {
        ZStack {
            // Amber progress arc — shows where timer was when paused
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: 0xE6A820).opacity(0.6),
                            Color(hex: 0xE6A820),
                            LiquidDesignTokens.Spectral.amber
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(hex: 0xE6A820).opacity(glowPulse ? 0.55 : 0.2), radius: glowPulse ? 14 : 6)
                .animation(FFMotion.progress, value: progress)
        }
    }

    // Overtime: different treatment for break vs focus
    private var overtimeRings: some View {
        ZStack {
            if case .onBreak = state {
                // Break overtime: full yellow ring + dark yellow overlay filling from 12:00
                Circle()
                    .stroke(
                        Color(hex: 0xE6A820).opacity(0.6),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .shadow(color: Color(hex: 0xE6A820).opacity(0.3), radius: 8)

                // Dark yellow overtime fill — progress beyond 1.0, map to 0→1 range
                let overtimeProgress = min(max(progress - 1.0, 0) / 0.5, 1.0)
                Circle()
                    .trim(from: 0, to: max(0.001, overtimeProgress))
                    .stroke(
                        Color(hex: 0xCC8800).opacity(0.9),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(hex: 0xCC8800).opacity(0.5), radius: 10)
                    .animation(FFMotion.progress, value: progress)
            } else {
                // Focus overtime: full green ring showing achievement
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(hex: 0x2D8B57).opacity(0.7),
                                Color(hex: 0x3DA86A),
                                Color(hex: 0x2D8B57).opacity(0.7)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .shadow(color: Color(hex: 0x3DA86A).opacity(glowPulse ? 0.5 : 0.2), radius: glowPulse ? 14 : 8)

                // Dark green overtime fill from 12:00
                let overtimeProgress = min(max(progress - 1.0, 0) / 0.5, 1.0)
                Circle()
                    .trim(from: 0, to: max(0.001, overtimeProgress))
                    .stroke(
                        Color(hex: 0x1A6B3D).opacity(0.9),
                        style: StrokeStyle(lineWidth: strokeWidth + 1, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(hex: 0x1A6B3D).opacity(0.4), radius: 8)
                    .animation(FFMotion.progress, value: progress)
            }
        }
    }

    // Outer halo arc — glowing progress indicator outside the main ring
    private var outerHaloArc: some View {
        Circle()
            .trim(from: 0, to: max(0.001, outerProgress))
            .stroke(
                outerGlowColor.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            .frame(width: ringSize + 6, height: ringSize + 6)
            .rotationEffect(.degrees(-90))
            .shadow(color: outerGlowColor.opacity(outerGlowOpacity), radius: outerGlowRadius)
            .animation(FFMotion.progress, value: progress)
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
