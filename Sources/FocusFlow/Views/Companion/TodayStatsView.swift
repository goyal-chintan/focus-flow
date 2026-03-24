import SwiftUI
import SwiftData

struct TodayStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(sort: \CoachInterruption.detectedAt) private var allCoachInterruptions: [CoachInterruption]

    private var dailyGoal: TimeInterval {
        max(60, allSettings.first?.dailyFocusGoal ?? 7200)
    }

    /// Sessions that overlap with today (includes cross-midnight sessions from yesterday)
    private var todaySessions: [FocusSession] {
        let start = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return allSessions.filter { session in
            guard session.type == .focus && session.actualDuration >= 60 else { return false }
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            return sessionEnd > start && session.startedAt < tomorrow
        }
    }

    /// Focus time attributed to today only (handles cross-midnight correctly)
    private func todayPortion(of session: FocusSession) -> TimeInterval {
        let start = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
        let overlapStart = max(session.startedAt, start)
        let overlapEnd = min(sessionEnd, tomorrow)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }

    @State private var showManualEntry = false
    @State private var dueReminders: [RemindersService.ReminderItem] = []
    @State private var showLoggedToast = false

    private var settings: AppSettings? { allSettings.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                dueRemindersStrip
                goalProgressBar
                summarySection
                nextBestBlockRow
                guardianLearnedRow
                streakRow

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
        .background(.clear)
        .sheet(isPresented: $showManualEntry) {
            ManualSessionView(onSave: {
                withAnimation(FFMotion.section) { showLoggedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(FFMotion.section) { showLoggedToast = false }
                }
            })
        }
        .overlay(alignment: .top) {
            if showLoggedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Session logged")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .task { await loadDueReminders() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today,")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                Text(Date().formatted(.dateTime.month(.wide).day()))
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
            }

            Text(heroMessage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

            HStack {
                Spacer()
                Button {
                    showManualEntry = true
                } label: {
                    Label("Log Session", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private var goalProgressBar: some View {
        let goalMinutes = dailyGoal / 60
        let actualMinutes = totalFocusTime / 60
        let progress = min(1.0, actualMinutes / goalMinutes)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LiquidDesignTokens.Spectral.primaryContainer, LiquidDesignTokens.Spectral.electricBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * progress))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Daily goal progress")
        .accessibilityValue("\(Int(min(1.0, (totalFocusTime / 60) / (dailyGoal / 60)) * 100)) percent complete")
    }

    private var summarySection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: "Earned Blocks",
                value: "\(earnedBlocksToday)",
                icon: "checkmark.seal.fill",
                color: .mint
            )

            StatCard(
                title: "Important Work",
                value: importantWorkSeconds.formattedFocusTime,
                icon: "bolt.fill",
                color: .blue
            )

            StatCard(
                title: "Recovered",
                value: "\(recoveredCount)",
                icon: "arrow.clockwise",
                color: .orange
            )

            StatCard(
                title: "Goal Runway",
                value: goalRunwayText,
                icon: "chart.line.uptrend.xyaxis",
                color: .gray
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var averageSessionLength: Int {
        guard completedCount > 0 else { return 0 }
        return Int(totalFocusTime / Double(completedCount) / 60)
    }

    // MARK: - Behavioral Metrics

    private var earnedBlocksToday: Int {
        completedCount
    }

    private var importantWorkSeconds: TimeInterval {
        todaySessions
            .filter { ($0.project?.workMode ?? .deepWork) != .admin }
            .reduce(0) { $0 + todayPortion(of: $1) }
    }

    private var recoveredCount: Int {
        let sessionIds = Set(todaySessions.map { $0.id })
        return allCoachInterruptions.filter { sessionIds.contains($0.sessionId) }.count
    }

    private var goalRunwayText: String {
        let remaining = max(0, dailyGoal - totalFocusTime)
        let blocks = Int(remaining / (25 * 60))
        return blocks > 0 ? "\(blocks) blocks" : "Goal met"
    }

    private var heroMessage: String {
        let count = earnedBlocksToday
        switch count {
        case 0:
            return "Start your first block"
        case 1:
            return "You protected 1 important block today"
        default:
            return "You protected \(count) important blocks today"
        }
    }

    private var suggestedNextProject: Project? {
        todaySessions.compactMap { $0.project }.first
    }

    private var guardianLearnedText: String? {
        let sessionIds = Set(todaySessions.map { $0.id })
        let todayInterruptions = allCoachInterruptions.filter { sessionIds.contains($0.sessionId) }
        guard !todayInterruptions.isEmpty else { return nil }
        let count = todayInterruptions.count
        return "Guardian tracked \(count) context event\(count == 1 ? "" : "s") today."
    }

    // MARK: - New Rows

    @ViewBuilder
    private var nextBestBlockRow: some View {
        if let nextProject = suggestedNextProject {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next best block")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(nextProject.name) · 25m")
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
                if earnedBlocksToday > 0 {
                    Text("✦ \(Int(totalFocusTime / 60))m")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.mint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        }
    }

    @ViewBuilder
    private var guardianLearnedRow: some View {
        if let text = guardianLearnedText {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        }
    }

    private var streakRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
            Text("Streak")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(currentStreak) day\(currentStreak == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
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
                                    .foregroundStyle(entry.key.color)

                                Text("\(entry.value)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()

                                Text(entry.key.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .obsidianGlass(cornerRadius: LiquidDesignTokens.CornerRadius.control)
                        }
                    }
                }

                let achievements = reflectedSessions.compactMap(\.achievement).filter { !$0.isEmpty }
                if !achievements.isEmpty {
                    let allItems = achievements.flatMap { text in
                        text.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(allItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .padding(.top, 2)

                                Text(item)
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

    // MARK: - Due Reminders Strip

    @ViewBuilder
    private var dueRemindersStrip: some View {
        if settings?.remindersIntegrationEnabled == true, !dueReminders.isEmpty {
            VStack(spacing: 6) {
                ForEach(dueReminders.prefix(3)) { reminder in
                    HStack(spacing: 10) {
                        Button { completeReminder(reminder) } label: {
                            Image(systemName: "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Text(reminder.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        Spacer()

                        if let due = reminder.dueDate {
                            Text(due.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }

                if dueReminders.count > 3 {
                    Text("\(dueReminders.count - 3) more in Reminders")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        }
    }

    private func loadDueReminders() async {
        guard settings?.remindersIntegrationEnabled == true else {
            dueReminders = []
            return
        }
        guard RemindersService.shared.authStatus == .authorized else {
            dueReminders = []
            return
        }
        let dayStart = Calendar.current.startOfDay(for: Date())
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            dueReminders = []
            return
        }
        let listId = settings?.selectedReminderListId.isEmpty == true ? nil : settings?.selectedReminderListId
        let fetched = await RemindersService.shared.fetchIncompleteReminders(
            listId: listId,
            dueDateStarting: dayStart,
            dueDateEnding: dayEnd
        )
        guard !Task.isCancelled else { return }
        dueReminders = fetched
    }

    private func completeReminder(_ reminder: RemindersService.ReminderItem) {
        Task {
            let didComplete = RemindersService.shared.completeReminder(identifier: reminder.id)
            guard didComplete else {
                print("[TodayStatsView] Failed to complete reminder: \(reminder.title)")
                return
            }
            withAnimation {
                dueReminders.removeAll { $0.id == reminder.id }
            }
        }
    }

}
