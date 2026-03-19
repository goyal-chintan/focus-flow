import SwiftUI
import SwiftData

struct TodayStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]

    /// Sessions that overlap with today (includes cross-midnight sessions from yesterday)
    private var todaySessions: [FocusSession] {
        let start = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return allSessions.filter { session in
            guard session.type == .focus && session.actualDuration >= 60 else { return false }
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            // Include if session overlaps today at all
            return sessionEnd > start && session.startedAt < tomorrow
        }
    }

    /// Focus time attributed to today only (handles cross-midnight correctly)
    private func todayPortion(of session: FocusSession) -> TimeInterval {
        let start = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
        let overlapStart = max(session.startedAt, start)
        let overlapEnd = min(sessionEnd, tomorrow)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }

    @State private var showManualEntry = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                summarySection

                if !projectBreakdown.isEmpty {
                    projectsSection
                }

                timelineSection

                let reflectedSessions = todaySessions.filter { $0.mood != nil || $0.achievement != nil }
                if !reflectedSessions.isEmpty {
                    reflectionsSection(reflectedSessions: reflectedSessions)
                }
            }
            .padding(24)
        }
        .background(.background)
        .sheet(isPresented: $showManualEntry) {
            ManualSessionView()
        }
    }

    private var headerSection: some View {
        LiquidSectionHeader(
            "Today",
            subtitle: Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        ) {
            Button {
                showManualEntry = true
            } label: {
                Label("Log Session", systemImage: "plus")
                    .font(LiquidDesignTokens.Typography.controlLabel)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        }
    }

    private var summarySection: some View {
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
    }

    private var projectsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Projects",
                    subtitle: "How today’s focus time was allocated"
                )

                VStack(spacing: 10) {
                    ForEach(projectBreakdown, id: \.name) { item in
                        ProjectTimeBar(
                            name: item.name,
                            duration: item.duration,
                            maxDuration: totalFocusTime,
                            color: item.color
                        )
                    }
                }
            }
            .padding(16)
        }
    }

    private var timelineSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Timeline",
                    subtitle: "\(todaySessions.count) focus session\(todaySessions.count == 1 ? "" : "s")"
                )

                SessionTimelineView(sessions: todaySessions)
            }
            .padding(16)
        }
    }

    private func reflectionsSection(reflectedSessions: [FocusSession]) -> some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Reflections",
                    subtitle: "Mood patterns and session notes"
                )

                let moodCounts = Dictionary(grouping: todaySessions.compactMap(\.mood), by: { $0 })
                    .mapValues(\.count)
                    .sorted { $0.value > $1.value }

                if !moodCounts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(moodCounts, id: \.key) { entry in
                            HStack(spacing: 5) {
                                Image(systemName: entry.key.icon)
                                    .font(.caption)
                                    .foregroundStyle(moodColor(entry.key))

                                Text("\(entry.value)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()

                                Text(entry.key.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.primary.opacity(0.07))
                            )
                        }
                    }
                }

                let achievements = reflectedSessions.compactMap(\.achievement).filter { !$0.isEmpty }
                if !achievements.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(achievements.enumerated()), id: \.offset) { _, achievement in
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
        }
    }

    private var totalFocusTime: TimeInterval {
        todaySessions.reduce(0) { $0 + todayPortion(of: $1) }
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
                map[name] = ((existing?.0 ?? 0) + todayPortion(of: session), existing?.1 ?? color)
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
