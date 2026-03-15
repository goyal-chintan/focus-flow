import SwiftUI
import SwiftData

struct TodayStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]

    private var todaySessions: [FocusSession] {
        let start = Calendar.current.startOfDay(for: Date())
        return allSessions.filter { $0.startedAt >= start && $0.type == .focus }
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
        var map: [String: TimeInterval] = [:]
        for session in todaySessions {
            map[session.label, default: 0] += session.actualDuration
        }
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .teal]
        return map.enumerated().map { idx, kv in
            ProjectItem(name: kv.key, duration: kv.value, color: colors[idx % colors.count])
        }.sorted { $0.duration > $1.duration }
    }

}
