import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    private let ringSize: CGFloat = 178
    private let lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.03))

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [ringColor.opacity(0.35), ringColor, ringColor.opacity(0.6)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.25), radius: 8)
                .animation(.easeInOut(duration: 0.75), value: progress)

            VStack(spacing: 4) {
                Text(timeString)
                    .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: true))

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
        }
        .frame(width: ringSize, height: ringSize)
    }

    private var ringColor: Color {
        switch state {
        case .focusing:
            .blue
        case .paused:
            .orange
        case .onBreak(let type):
            type == .longBreak ? .purple : .green
        case .idle:
            .secondary.opacity(0.35)
        }
    }
}
