import SwiftUI

struct ProjectTimeBar: View {
    let name: String
    let duration: TimeInterval
    let maxDuration: TimeInterval
    let color: Color

    @State private var animatedRatio: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(formattedTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * animatedRatio, height: 6)
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animatedRatio = maxDuration > 0 ? min(1, duration / maxDuration) : 0
            }
        }
        .onChange(of: duration) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedRatio = maxDuration > 0 ? min(1, duration / maxDuration) : 0
            }
        }
    }

    private var formattedTime: String {
        let m = Int(duration) / 60
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
}
