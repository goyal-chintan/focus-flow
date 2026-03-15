import SwiftUI
import SwiftData

struct TodayStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]

    private var todaySessions: [FocusSession] {
        let start = Calendar.current.startOfDay(for: Date())
        return allSessions.filter { $0.startedAt >= start && $0.type == .focus && $0.actualDuration >= 60 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary cards
                HStack(spacing: 12) {
                    StatCard(
                        title: "Focus Time",
                        value: totalFocusTime.formattedFocusTime,
                        icon: "timer",
                        color: .blue
                    )

                    StatCard(
                        title: "Sessions",
                        value: "\(completedCount)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )

                    StatCard(
                        title: "Streak",
                        value: "\(currentStreak)",
                        icon: "flame.fill",
                        color: .orange
                    )
                }

                // Per-project breakdown
                if !projectBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Projects")
                            .font(.headline)

                        ForEach(projectBreakdown, id: \.name) { item in
                            ProjectTimeBar(
                                name: item.name,
                                duration: item.duration,
                                maxDuration: totalFocusTime,
                                color: item.color
                            )
                        }
                    }
                    .padding(16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                }

                // Session timeline
                VStack(alignment: .leading, spacing: 14) {
                    Text("Timeline")
                        .font(.headline)

                    SessionTimelineView(sessions: todaySessions)
                }
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

                // Reflections section
                let reflectedSessions = todaySessions.filter { $0.mood != nil || $0.achievement != nil }
                if !reflectedSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Reflections")
                            .font(.headline)

                        // Mood distribution
                        let moodCounts = Dictionary(grouping: todaySessions.compactMap(\.mood), by: { $0 })
                            .mapValues(\.count)
                            .sorted { $0.value > $1.value }

                        if !moodCounts.isEmpty {
                            HStack(spacing: 12) {
                                ForEach(moodCounts, id: \.key) { mood, count in
                                    HStack(spacing: 4) {
                                        Image(systemName: mood.icon)
                                            .font(.caption)
                                            .foregroundStyle(moodColor(mood))
                                        Text("\(count)")
                                            .font(.subheadline.weight(.medium))
                                        Text(mood.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        // Achievements list
                        let achievements = reflectedSessions.compactMap(\.achievement).filter { !$0.isEmpty }
                        if !achievements.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(achievements, id: \.self) { achievement in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                            .padding(.top, 2)
                                        Text(achievement)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(24)
        }
        .background(.background)
    }

    private var totalFocusTime: TimeInterval {
        todaySessions.reduce(0) { $0 + $1.actualDuration }
    }

    private var completedCount: Int {
        todaySessions.filter(\.completed).count
    }

    private var currentStreak: Int {
        var streak = 0
        for session in todaySessions.reversed() {
            if session.completed { streak += 1 } else { break }
        }
        return streak
    }

    private struct ProjectItem {
        let name: String
        let duration: TimeInterval
        let color: Color
    }

    private func moodColor(_ mood: FocusMood) -> Color {
        switch mood {
        case .distracted: .orange
        case .neutral: .secondary
        case .focused: .blue
        case .deepFocus: .purple
        }
    }

    private var projectBreakdown: [ProjectItem] {
        var map: [String: (TimeInterval, Color)] = [:]
        for session in todaySessions {
            if session.hasSplits {
                // Use split data for sessions with time splits
                for split in session.splits {
                    let name = split.label
                    let color: Color = {
                        if let c = split.project?.color { return colorFromName(c) }
                        if let c = session.project?.color { return colorFromName(c) }
                        return .blue
                    }()
                    let existing = map[name]
                    map[name] = ((existing?.0 ?? 0) + split.duration, existing?.1 ?? color)
                }
            } else {
                // Use session-level data
                let name = session.label
                let color: Color = {
                    if let c = session.project?.color { return colorFromName(c) }
                    return .blue
                }()
                let existing = map[name]
                map[name] = ((existing?.0 ?? 0) + session.actualDuration, existing?.1 ?? color)
            }
        }
        return map.map { ProjectItem(name: $0.key, duration: $0.value.0, color: $0.value.1) }
            .sorted { $0.duration > $1.duration }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "mint": return .mint
        default: return .blue
        }
    }

}
