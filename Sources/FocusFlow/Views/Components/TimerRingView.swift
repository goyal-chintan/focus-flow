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
    /// The overtime is a break running over (`TimerViewModel.isBreakOvertime`). A finished break
    /// reports `.idle`, so `state` alone never says it: without this the ring drew a block's overtime.
    var isBreakOvertime: Bool = false
    var labelColorOverride: Color? = nil

    private let ringSize: CGFloat = 170
    private let strokeWidth: CGFloat = 6

    @State private var glowPulse: Bool = false
    @State private var breathingOpacity: Double = 0.06
    @State private var breakBreathingOpacity: Double = 0.06
    @State private var completionBurst: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Glow reads as light on near-black; on frosted white it looks like a smudge, so light
    /// mode keeps under half of it and leans on the disc's drop shadow for depth.
    private var glowScale: Double { colorScheme == .dark ? 1 : 0.4 }
    /// State labels: soft in dark, near-solid in light so the deep inks keep their contrast.
    private var labelAlpha: Double { colorScheme == .dark ? 0.65 : 0.9 }

    @Environment(\.motionPaused) private var motionPaused
    private var disableMotion: Bool { reduceMotion || evidenceMode || motionPaused }

    /// Amber break-overrun ring, not the blue and green of a block's overtime.
    private var isBreakOverrun: Bool {
        guard isOvertime else { return false }
        if case .onBreak = state { return true }
        return isBreakOvertime
    }

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
        guard isBreakOverrun else { return strokeWidth }
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
        if isBreakOverrun {
            // Escalate: >1.0 progress means overtime; use progress magnitude for severity
            if progress > 1.5 { return FFPalette.destructive }
            if progress > 1.0 { return RingInk.amber }
            return ringGlowColor
        }
        switch state {
        case .paused:
            if pauseDuration > 300 { return FFPalette.destructive }
            if pauseDuration > 180 { return RingInk.amber }
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
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(breathingOpacity * glowScale))
                    .blur(radius: 12)
                    .frame(width: ringSize + 20, height: ringSize + 20)
                    .animation(disableMotion ? nil : FFMotion.breathing, value: breathingOpacity)
            }

            // Break recovery breathing — calms in last 40%
            if case .onBreak = state, !disableMotion {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(breakBreathingOpacity * glowScale))
                    .blur(radius: 12)
                    .frame(width: ringSize + 20, height: ringSize + 20)
                    .animation(disableMotion ? nil : FFMotion.breathing, value: breakBreathingOpacity)
            }

            // Completion mint burst
            if completionBurst && !disableMotion {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(0.3 * glowScale))
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
                .fill(RingInk.disc)
                .frame(width: ringSize, height: ringSize)
                .shadow(color: RingInk.discShadow, radius: 10, y: 4)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.clear, RingInk.discEdge],
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
                    .stroke(RingInk.idleTrack, lineWidth: strokeWidth)
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
                    .shadow(color: ringGlowColor.opacity((glowPulse ? 0.65 : 0.28) * glowScale), radius: glowPulse ? 18 : 10)
                    .shadow(color: ringGlowColor.opacity((glowPulse ? 0.25 : 0.08) * glowScale), radius: glowPulse ? 28 : 18)
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
                        color: pauseRingColor.opacity(labelAlpha),
                        tracking: 2.2
                    )

                    if pauseDuration > 180 {
                        Text("Consider resuming")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
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
                        color: (labelColorOverride ?? labelColor).opacity(labelAlpha),
                        tracking: 2.2
                    )
                    .contentTransition(.interpolate)
                    .animation(disableMotion ? nil : FFMotion.section, value: label)

                    if case .onBreak = state, overrunSeconds > 0 {
                        Text("+\(Int(overrunSeconds / 60))m over")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
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
            if isBreakOverrun {
                return "Break ran over"
            }
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
        case .focusing: RingInk.focusText
        case .paused: LiquidDesignTokens.Spectral.amber
        case .onBreak: LiquidDesignTokens.Spectral.mint
        }
    }

    private var ringGradient: AngularGradient {
        switch state {
        case .focusing:
            AngularGradient(
                colors: [
                    RingInk.blueTail,
                    RingInk.blue,
                    RingInk.bluePeak,
                    RingInk.blue,
                    RingInk.blueTail
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
            let tickColor = isMajor ? RingInk.tickMajor : RingInk.tickMinor

            Rectangle()
                .fill(tickColor)
                .frame(width: 1, height: tickLength)
                .offset(y: -(ringSize / 2) + tickLength / 2 - 1)
                .rotationEffect(.degrees(Double(tick) * 6))
        }
    }

    // Pause ring color based on how long the user has been paused
    private var pauseRingColor: Color {
        if pauseDuration > 300 { return FFPalette.destructive }
        if pauseDuration > 180 { return RingInk.amberDeep }
        return RingInk.amber
    }

    private var pauseRingColorLight: Color {
        if pauseDuration > 300 { return FFPalette.destructive.opacity(0.6) }
        if pauseDuration > 180 { return RingInk.amberDeep.opacity(0.6) }
        return RingInk.amber.opacity(0.6)
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
                .shadow(color: pauseRingColor.opacity((glowPulse ? 0.55 : 0.2) * glowScale), radius: glowPulse ? 14 : 6)
                .animation(disableMotion ? nil : FFMotion.progress, value: progress)
                .animation(disableMotion ? nil : FFMotion.progress, value: pauseDuration)
        }
    }

    // Overtime: different treatment for break vs focus
    private var overtimeRings: some View {
        ZStack {
            if isBreakOverrun {
                // Break overtime: full yellow ring + dark yellow overlay filling from 12:00
                Circle()
                    .stroke(
                        RingInk.amber.opacity(0.6),
                        style: StrokeStyle(lineWidth: breakOvertimeStrokeWidth, lineCap: .round)
                    )
                    .shadow(color: RingInk.amber.opacity(0.3 * glowScale), radius: 8)
                    .animation(disableMotion ? nil : FFMotion.progress, value: overrunSeconds)

                // Dark yellow overtime fill — progress beyond 1.0, map to 0→1 range
                let overtimeProgress = min(max(progress - 1.0, 0) / 0.5, 1.0)
                Circle()
                    .trim(from: 0, to: max(0.001, overtimeProgress))
                    .stroke(
                        RingInk.amberDeep.opacity(0.9),
                        style: StrokeStyle(lineWidth: breakOvertimeStrokeWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: RingInk.amberDeep.opacity(0.5 * glowScale), radius: 10)
                        .animation(disableMotion ? nil : FFMotion.progress, value: progress)
                        .animation(disableMotion ? nil : FFMotion.progress, value: overrunSeconds)
            } else {
                // Focus overtime: blue ring base with green overlay growing as overtime increases
                // Base: full blue ring (same as focusing)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                RingInk.blueTail,
                                RingInk.blue,
                                RingInk.bluePeak,
                                RingInk.blue,
                                RingInk.blueTail
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .shadow(color: RingInk.blue.opacity((glowPulse ? 0.5 : 0.2) * glowScale), radius: glowPulse ? 14 : 8)

                // Green overlay: grows from 12 o'clock as overtime increases
                let overtimeProgress = min(max(progress - 1.0, 0) / 0.5, 1.0)
                if overtimeProgress > 0 {
                    Circle()
                        .trim(from: 0, to: max(0.001, overtimeProgress))
                        .stroke(
                            RingInk.green.opacity(0.9),
                            style: StrokeStyle(lineWidth: strokeWidth + 1, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: RingInk.green.opacity((glowPulse ? 0.5 : 0.25) * glowScale), radius: glowPulse ? 12 : 6)
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
            .shadow(color: outerGlowColor.opacity(outerGlowOpacity * glowScale), radius: outerGlowRadius)
            .animation(disableMotion ? nil : FFMotion.progress, value: progress)
    }

    private var ringColor: Color {
        switch state {
        case .focusing:
            RingInk.idleBlue
        case .paused:
            LiquidDesignTokens.Spectral.amberDark
        case .onBreak(let type):
            type == .longBreak ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.mintDark
        case .idle:
            RingInk.idleBlueDim
        }
    }

    private var ringGlowColor: Color {
        switch state {
        case .focusing:
            RingInk.blue
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

/// Timer ring colours. Dark: a smoked-glass disc with luminous arcs (unchanged). Light: a raised
/// porcelain dial (white disc, soft drop shadow) with deep ink arcs and text
/// (light-mode design 2026-11-18).
private enum RingInk {
    static let disc = Color.adaptive(light: 0xFFFFFF, dark: 0x000000, lightAlpha: 0.92, darkAlpha: 0.5)
    static let discEdge = Color.adaptive(light: 0x000000, dark: 0x000000, lightAlpha: 0.035, darkAlpha: 0.3)
    static let discShadow = Color.adaptive(light: 0x1C2440, dark: 0x000000, lightAlpha: 0.14, darkAlpha: 0)
    static let idleTrack = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.04)
    static let tickMajor = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.12)
    static let tickMinor = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.06)
    static let focusText = Color.adaptive(light: 0x14161C, dark: 0xFFFFFF)

    static let blueTail = Color.adaptive(light: 0xB7CDF5, dark: 0x3A4F85)
    static let blue = Color.adaptive(light: 0x2A72E8, dark: 0x5B96F8)
    static let bluePeak = Color.adaptive(light: 0x1A5FD0, dark: 0x7DB4FF)
    static let idleBlue = Color.adaptive(light: 0x7F9BD0, dark: 0x506392)
    static let idleBlueDim = Color.adaptive(light: 0x8FA3C8, dark: 0x4C5A80)
    static let amber = Color.adaptive(light: 0xB86E00, dark: 0xE6A820)
    static let amberDeep = Color.adaptive(light: 0x9A5200, dark: 0xCC8800)
    static let green = Color.adaptive(light: 0x15805A, dark: 0x3DA86A)
}
