import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    @State private var glowPulse = false

    private var isRunning: Bool {
        if case .focusing = state { return true }
        if case .onBreak = state { return true }
        return false
    }

    var body: some View {
        ZStack {
            // Glow layer behind the ring
            Circle()
                .stroke(lineWidth: 24)
                .foregroundStyle(ringColor.opacity(glowPulse ? 0.25 : 0.10))
                .blur(radius: 12)

            // Track ring
            Circle()
                .stroke(lineWidth: 12)
                .foregroundStyle(.quaternary)

            // Progress ring
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.5), radius: 6, x: 0, y: 0)
                .animation(.smooth(duration: 0.9), value: progress)

            // Center content
            VStack(spacing: 6) {
                Text(timeString)
                    .font(.system(size: 42, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.smooth, value: timeString)
                    .scaleEffect(isRunning && glowPulse ? 1.02 : 1.0)

                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: label)
            }
        }
        .frame(width: 180, height: 180)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: state) { _, _ in startPulseIfNeeded() }
    }

    private func startPulseIfNeeded() {
        if isRunning {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                glowPulse = false
            }
        }
    }

    private var ringColor: Color {
        switch state {
        case .focusing: .blue
        case .paused: .blue.opacity(0.5)
        case .onBreak(let type):
            type == .longBreak ? .purple : .green
        case .idle: .secondary
        }
    }

    private var ringGradient: AngularGradient {
        let color = ringColor
        return AngularGradient(
            colors: [color.opacity(0.4), color],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * max(0, min(1, progress)))
        )
    }
}
