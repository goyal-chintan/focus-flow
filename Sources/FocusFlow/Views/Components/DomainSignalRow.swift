import SwiftUI

struct DomainSignalRow: View {
    let row: CompanionAnalyticsRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(TimeInterval(row.totalSeconds).formattedFocusTime)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    Label(categoryBadge.title, systemImage: categoryBadge.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(categoryBadge.tint)
                        .labelStyle(.titleAndIcon)

                    if row.duringFocusSeconds > 0 || row.outsideFocusSeconds > 0 {
                        Text(activitySummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.domainSignal.\(row.bundleIdentifier)")
        .accessibilityLabel("\(row.label), \(categoryBadge.title), \(TimeInterval(row.totalSeconds).formattedFocusTime), \(activitySummary)")
    }

    private var activitySummary: String {
        var parts: [String] = []

        if row.duringFocusSeconds > 0 {
            parts.append("\(TimeInterval(row.duringFocusSeconds).formattedFocusTime) during focus")
        }

        if row.outsideFocusSeconds > 0 {
            parts.append("\(TimeInterval(row.outsideFocusSeconds).formattedFocusTime) outside focus")
        }

        return parts.joined(separator: " · ")
    }

    private var categoryBadge: (title: String, icon: String, tint: Color) {
        switch row.category {
        case .productive:
            return ("Productive", "checkmark.circle.fill", .mint)
        case .neutral:
            return ("Neutral", "minus.circle.fill", Color.secondary)
        case .distracting:
            return ("Distracting", "exclamationmark.triangle.fill", .orange)
        }
    }
}
