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
            VStack(spacing: FFSpacing.lg) {
                PremiumSurface(style: .hero) {
                    PremiumSectionHeader(
                        "Today",
                        eyebrow: "Dashboard",
                        subtitle: heroSubtitle
                    ) {
                        Button {
                            showManualEntry = true
                        } label: {
                            Label("Log Session", systemImage: "plus.circle.fill")
                                .font(FFType.meta)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(FFColor.focus)
                    }
                }

                HStack(spacing: FFSpacing.sm) {
                    StatCard(
                        title: "Focus Time",
                        value: totalFocusTime.formattedFocusTime,
                        icon: "timer.circle.fill",
                        color: FFColor.focus
                    )

                    StatCard(
                        title: "Sessions",
                        value: "\(completedCount)",
                        icon: "checkmark.circle.fill",
                        color: FFColor.success
                    )

                    StatCard(
                        title: "Streak",
                        value: "\(currentStreak)",
                        icon: "flame.fill",
                        color: FFColor.warning
                    )
                }

                if !projectBreakdown.isEmpty {
                    PremiumSurface(style: .card) {
                        PremiumSectionHeader(
                            "Projects",
                            eyebrow: "Distribution",
                            subtitle: "Where your time went today."
                        )
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

                PremiumSurface(style: .card) {
                    PremiumSectionHeader(
                        "Timeline",
                        eyebrow: "Sessions",
                        subtitle: todaySessions.isEmpty ? "No focus sessions logged yet." : "Tap any session to edit its details."
                    )
                    SessionTimelineView(sessions: todaySessions)
                }

                let reflectedSessions = todaySessions.filter { $0.mood != nil || $0.achievement != nil }
                if !reflectedSessions.isEmpty {
                    PremiumSurface(style: .card) {
                        PremiumSectionHeader(
                            "Reflections",
                            eyebrow: "Review",
                            subtitle: "Mood trends and the outcomes you captured."
                        )

                        let moodCounts = Dictionary(grouping: todaySessions.compactMap(\.mood), by: { $0 })
                            .mapValues(\.count)
                            .sorted { $0.value > $1.value }

                        if !moodCounts.isEmpty {
                            HStack(spacing: FFSpacing.sm) {
                                ForEach(moodCounts, id: \.key) { mood, count in
                                    reflectionPill(for: mood, count: count)
                                }
                            }
                        }

                        let achievements = reflectedSessions.compactMap(\.achievement).filter { !$0.isEmpty }
                        if !achievements.isEmpty {
                            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                                ForEach(achievements, id: \.self) { achievement in
                                    HStack(alignment: .top, spacing: FFSpacing.sm) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(FFColor.success)
                                            .padding(.top, 3)
                                        Text(achievement)
                                            .font(FFType.body)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, FFSpacing.md)
                                    .padding(.vertical, FFSpacing.sm)
                                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
            .padding(FFSpacing.lg)
        }
        .sheet(isPresented: $showManualEntry) {
            ManualSessionView()
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

    private var heroSubtitle: String {
        if todaySessions.isEmpty {
            return "No sessions logged yet. Start focusing or add one manually."
        }
        return "\(completedCount) completed \u{00B7} \(totalFocusTime.formattedFocusTime) of intentional work today"
    }

    private func reflectionPill(for mood: FocusMood, count: Int) -> some View {
        HStack(spacing: FFSpacing.xs) {
            Image(systemName: mood.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(moodColor(mood))
            Text("\(count)")
                .font(FFType.meta.weight(.semibold))
            Text(mood.rawValue)
                .font(FFType.meta)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.xs)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.1))
        }
    }

    private func moodColor(_ mood: FocusMood) -> Color {
        switch mood {
        case .distracted: FFColor.warning
        case .neutral: .secondary
        case .focused: FFColor.focus
        case .deepFocus: FFColor.deepFocus
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
