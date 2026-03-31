import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState
    let isOvertime: Bool
    var evidenceMode: Bool = false
    var pauseDuration: TimeInterval = 0
    var pauseTimeString: String = "0:00"
    var overrunSeconds: TimeInterval = 0
    var labelColorOverride: Color? = nil

    private let ringSize: CGFloat = 170
    private let strokeWidth: CGFloat = 6

    @State private var glowPulse: Bool = false
    @State private var breathingOpacity: Double = 0.06
    @State private var breakBreathingOpacity: Double = 0.06
    @State private var completionBurst: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var disableMotion: Bool { reduceMotion || evidenceMode }

    private var isActive: Bool {
        switch state {
        case .focusing, .paused, .onBreak: true
        case .idle: false
        }
    }

    // MARK: - Motion Computed Properties

    private var pauseStrokeWidth: CGFloat {
        guard case .paused = state else { return strokeWidth }
        if pauseDuration > 180 { return 3.5 }
        if pauseDuration > 60 {
            let t = (pauseDuration - 60) / 120
            return strokeWidth - (CGFloat(t) * 1.0)
        }
        let t = min(pauseDuration / 60, 1.0)
        return strokeWidth - (CGFloat(t) * 1.5)
    }

    private var breakBreathingAmplitude: Double {
        guard case .onBreak = state else { return 0 }
        if progress > 0.6 {
            let t = (progress - 0.6) / 0.4
            return 0.14 - (t * 0.08)
        }
        return 0.14
    }

    private var breakOvertimeStrokeWidth: CGFloat {
        guard case .onBreak = state, isOvertime else { return strokeWidth }
        if overrunSeconds > 180 { return 3.5 }
        if overrunSeconds > 60 {
            let t = (overrunSeconds - 60) / 120
            return strokeWidth - (CGFloat(t) * 1.0)
        }
        let t = min(overrunSeconds / 60, 1.0)
        return strokeWidth - (CGFloat(t) * 1.5)
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
            // Idle breathing glow — CPU-safe, only animates opacity
            if !isActive && !disableMotion {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(breathingOpacity))
                    .blur(radius: 12)
                    .frame(width: ringSize + 20, height: ringSize + 20)
                    .animation(disableMotion ? nil : FFMotion.breathing, value: breathingOpacity)
            }

            // Break recovery breathing — calms in last 40%
            if case .onBreak = state, !disableMotion {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(breakBreathingOpacity))
                    .blur(radius: 12)
                    .frame(width: ringSize + 20, height: ringSize + 20)
                    .animation(disableMotion ? nil : FFMotion.breathing, value: breakBreathingOpacity)
            }

            // Completion mint burst
            if completionBurst && !disableMotion {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(0.3))
                    .blur(radius: 20)
                    .frame(width: ringSize + 40, height: ringSize + 40)
                    .transition(.opacity)
            }

            // Outer halo — only visible when active (no gray track in idle)
            if isActive {
                outerHaloArc
            }

            // Tick marks (watch-face aesthetic)
            tickMarks
                .accessibilityHidden(true)

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

            // Main ring — state-dependent (isOvertime checked first so green ring shows even when state is idle during completion)
            if isOvertime {
                overtimeRings
            } else if state == .idle {
                // Idle: very subtle track only (no heavy gray)
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: strokeWidth)
            } else if state == .paused {
                pausedRings
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
                    .animation(disableMotion ? nil : FFMotion.progress, value: progress)
            }

            // Center text
            VStack(spacing: 5) {
                if state == .paused {
                    // Show pause elapsed time prominently — color escalates with duration
                    Text(pauseTimeString)
                        .font(.system(size: 36, weight: .ultraLight, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(pauseRingColor)
                        .contentTransition(.numericText(countsDown: false))

                    TrackedLabel(
                        text: "PAUSED",
                        font: .system(size: 10, weight: .medium),
                        color: pauseRingColor.opacity(0.65),
                        tracking: 2.2
                    )

                    if pauseDuration > 180 {
                        Text("Consider resuming")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(pauseRingColor.opacity(0.8))
                            .transition(.opacity)
                    }

                    // Show frozen focus time smaller below
                    Text(timeString)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.5))
                        .padding(.top, 2)
                } else {
                    Text(timeString)
                        .font(.system(size: 36, weight: .ultraLight, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timeTextColor)
                        .contentTransition(.numericText(countsDown: true))

                    TrackedLabel(
                        text: label,
                        font: .system(size: 10, weight: .medium),
                        color: (labelColorOverride ?? labelColor).opacity(0.65),
                        tracking: 2.2
                    )
                    .contentTransition(.interpolate)
                    .animation(disableMotion ? nil : FFMotion.section, value: label)

                    if case .onBreak = state, overrunSeconds > 0 {
                        Text("+\(Int(overrunSeconds / 60))m over")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(width: ringSize + 6, height: ringSize + 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(timeString)")
        .accessibilityValue({
            if isOvertime {
                return "Overtime, session complete"
            }
            return label
        }())
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                if disableMotion {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        glowPulse = true
                    }
                } else {
                    withAnimation(FFMotion.commit) {
                        glowPulse = true
                    }
                }
                // Stop idle breathing immediately (view is removed, reset state)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    breathingOpacity = 0.06
                }
            } else {
                if disableMotion {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        glowPulse = false
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.4)) {
                        glowPulse = false
                    }
                }
                if !disableMotion {
                    breathingOpacity = 0.14
                }
            }
        }
        .onChange(of: isOvertime) { oldValue, newValue in
            if newValue && !oldValue && state == .focusing && !disableMotion {
                withAnimation(FFMotion.reward) {
                    completionBurst = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        completionBurst = false
                    }
                }
            }
        }
        .onChange(of: state, initial: true) { _, newState in
            if case .onBreak = newState, !disableMotion {
                breakBreathingOpacity = breakBreathingAmplitude
            } else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    breakBreathingOpacity = 0.06
                }
            }
        }
        .onChange(of: progress) { _, _ in
            if case .onBreak = state, progress > 0.6, !disableMotion {
                breakBreathingOpacity = breakBreathingAmplitude
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

    // Pause ring color based on how long the user has been paused
    private var pauseRingColor: Color {
        if pauseDuration > 300 { return .red }
        if pauseDuration > 180 { return Color(hex: 0xCC8800) } // dark yellow
        return Color(hex: 0xE6A820) // amber
    }

    private var pauseRingColorLight: Color {
        if pauseDuration > 300 { return .red.opacity(0.6) }
        if pauseDuration > 180 { return Color(hex: 0xCC8800).opacity(0.6) }
        return Color(hex: 0xE6A820).opacity(0.6)
    }

    // Paused: arc showing how far timer reached, color escalates with pause duration
    private var pausedRings: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [
                            pauseRingColorLight,
                            pauseRingColor,
                            pauseRingColor
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: pauseStrokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: pauseRingColor.opacity(glowPulse ? 0.55 : 0.2), radius: glowPulse ? 14 : 6)
                .animation(disableMotion ? nil : FFMotion.progress, value: progress)
                .animation(disableMotion ? nil : FFMotion.progress, value: pauseDuration)
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
                        style: StrokeStyle(lineWidth: breakOvertimeStrokeWidth, lineCap: .round)
                    )
                    .shadow(color: Color(hex: 0xE6A820).opacity(0.3), radius: 8)
                    .animation(disableMotion ? nil : FFMotion.progress, value: overrunSeconds)

                // Dark yellow overtime fill — progress beyond 1.0, map to 0→1 range
                let overtimeProgress = min(max(progress - 1.0, 0) / 0.5, 1.0)
                Circle()
                    .trim(from: 0, to: max(0.001, overtimeProgress))
                    .stroke(
                        Color(hex: 0xCC8800).opacity(0.9),
                        style: StrokeStyle(lineWidth: breakOvertimeStrokeWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color(hex: 0xCC8800).opacity(0.5), radius: 10)
                        .animation(disableMotion ? nil : FFMotion.progress, value: progress)
                        .animation(disableMotion ? nil : FFMotion.progress, value: overrunSeconds)
            } else {
                // Focus overtime: blue ring base with green overlay growing as overtime increases
                // Base: full blue ring (same as focusing)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(hex: 0x3A4F85),
                                Color(hex: 0x5B96F8),
                                Color(hex: 0x7DB4FF),
                                Color(hex: 0x5B96F8),
                                Color(hex: 0x3A4F85)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .shadow(color: Color(hex: 0x5B96F8).opacity(glowPulse ? 0.5 : 0.2), radius: glowPulse ? 14 : 8)

                // Green overlay: grows from 12 o'clock as overtime increases
                let overtimeProgress = min(max(progress - 1.0, 0) / 0.5, 1.0)
                if overtimeProgress > 0 {
                    Circle()
                        .trim(from: 0, to: max(0.001, overtimeProgress))
                        .stroke(
                            Color(hex: 0x3DA86A).opacity(0.9),
                            style: StrokeStyle(lineWidth: strokeWidth + 1, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color(hex: 0x3DA86A).opacity(glowPulse ? 0.5 : 0.25), radius: glowPulse ? 12 : 6)
                        .animation(disableMotion ? nil : FFMotion.progress, value: progress)
                }
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
            .animation(disableMotion ? nil : FFMotion.progress, value: progress)
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
