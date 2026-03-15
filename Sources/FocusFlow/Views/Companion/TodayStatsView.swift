import SwiftUI
import SwiftData

struct TodayStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @State private var cardsAppeared = false

    private var todaySessions: [FocusSession] {
        let start = Calendar.current.startOfDay(for: Date())
        return allSessions.filter { $0.startedAt >= start && $0.type == .focus }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Focus")
                        .font(.title.weight(.bold))
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Summary cards
                HStack(spacing: 12) {
                    StatCard(
                        title: "Focus Time",
                        value: totalFocusTime.formattedFocusTime,
                        icon: "timer",
                        color: .blue
                    )
                    .opacity(cardsAppeared ? 1 : 0)
                    .offset(y: cardsAppeared ? 0 : 12)

                    StatCard(
                        title: "Sessions",
                        value: "\(completedCount)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    .opacity(cardsAppeared ? 1 : 0)
                    .offset(y: cardsAppeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08), value: cardsAppeared)

                    StatCard(
                        title: "On a Streak",
                        value: "\(currentStreak)",
                        icon: "flame.fill",
                        color: .orange
                    )
                    .opacity(cardsAppeared ? 1 : 0)
                    .offset(y: cardsAppeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.16), value: cardsAppeared)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: cardsAppeared)

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
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                // Session timeline
                VStack(alignment: .leading, spacing: 14) {
                    Text("Timeline")
                        .font(.headline)

                    SessionTimelineView(sessions: todaySessions)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .background(.background)
        .onAppear {
            withAnimation {
                cardsAppeared = true
            }
        }
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
