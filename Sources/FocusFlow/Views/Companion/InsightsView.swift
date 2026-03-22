import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(sort: \AppUsageRecord.date) private var usageRecords: [AppUsageRecord]
    @Query(sort: \AppUsageEntry.date) private var appUsageEntries: [AppUsageEntry]
    @State private var selectedHour: Int? = nil
    @State private var showAllInsights = false
    @State private var showScienceTips = false
    @State private var showAppUsage = false

    private var dailyGoal: TimeInterval {
        allSettings.first?.dailyFocusGoal ?? 7200
    }

    private var focusSessions: [FocusSession] {
        allSessions.filter { $0.type == .focus }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                focusScoreSection
                behavioralInsightsSection
                coachInsightsSection
                analyticsGridSection
                trendsAndBreaksSection
                scienceTipsSection
                appUsageSection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .animation(FFMotion.section, value: selectedHour)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Insights")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

            Text("Patterns and productivity analysis from your focus sessions.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Focus Score Hero

    private var focusScoreSection: some View {
        LiquidGlassPanel {
            VStack(spacing: 16) {
                if hasEnoughDataForScore {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                            .frame(width: 100, height: 100)

                        Circle()
                            .trim(from: 0, to: CGFloat(focusScore) / 100.0)
                            .stroke(
                                focusScoreColor,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 100, height: 100)
                            .animation(.spring(response: 1.0, dampingFraction: 0.8), value: focusScore)

                        VStack(spacing: 2) {
                            Text("\(focusScore)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                            Text(focusScoreLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Focus score: \(focusScore) out of 100, \(focusScoreLabel)")

                    Text(focusScoreSummary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Focus Score")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Complete a few more sessions to unlock your personalized Focus Score. We need at least 3 sessions to calculate meaningful patterns.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var hasEnoughDataForScore: Bool {
        focusSessions.count >= 3
    }

    private var focusScore: Int {
        let consistency = calculateConsistency()
        let completionRate = calculateCompletionRate()
        let goalAdherence = calculateGoalAdherence()
        return Int((consistency * 0.3 + completionRate * 0.3 + goalAdherence * 0.4) * 100)
    }

    private var focusScoreColor: Color {
        switch focusScore {
        case 80...100: .green
        case 50..<80: .blue
        case 30..<50: .orange
        default: .red
        }
    }

    private var focusScoreLabel: String {
        switch focusScore {
        case 80...100: "EXCELLENT"
        case 50..<80: "GOOD"
        case 30..<50: "BUILDING"
        default: "STARTING"
        }
    }

    private var focusScoreSummary: String {
        switch focusScore {
        case 80...100: "Outstanding focus — keep this rhythm going"
        case 50..<80: "Good progress — building strong habits"
        case 30..<50: "Getting started — consistency is key"
        default: "Every session counts — start small"
        }
    }

    private func calculateConsistency() -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysWithSessions = (0..<7).filter { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return focusSessions.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
        }.count
        return Double(daysWithSessions) / 7.0
    }

    private func calculateCompletionRate() -> Double {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date()))!
        let recentSessions = focusSessions.filter { $0.startedAt >= weekAgo }
        guard !recentSessions.isEmpty else { return 0 }
        let completed = recentSessions.filter(\.completed).count
        return Double(completed) / Double(recentSessions.count)
    }

    private func calculateGoalAdherence() -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let goal = dailyGoal
        let daysMetGoal = (0..<7).filter { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dayTotal = focusSessions
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0.0) { $0 + $1.actualDuration }
            return dayTotal >= goal
        }.count
        return Double(daysMetGoal) / 7.0
    }

    // MARK: - Behavioral Insights (NL)

    private var behavioralInsightsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Your Focus Profile",
                    subtitle: "Personalized insights from your patterns"
                )

                VStack(spacing: 10) {
                    if behavioralInsights.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("Complete a few more sessions to unlock personalized insights")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 12)
                            Spacer()
                        }
                    } else {
                        ForEach(Array(behavioralInsights.enumerated()), id: \.offset) { _, insight in
                            insightCard(insight)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Coach Insights (Weekly Report)

    @ViewBuilder
    private var coachInsightsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Coach Report",
                    subtitle: "Science-based coaching from your patterns"
                )

                let report = buildCoachReport()

                if report.totalSessions < 3 {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "brain.head.profile.fill")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text("Complete 3+ sessions to unlock personalized coaching insights")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    // Hero metrics row
                    HStack(spacing: 12) {
                        coachMetricCard(
                            value: "\(Int(report.completionRate * 100))%",
                            label: "Completion",
                            color: report.completionRate > 0.7
                                ? LiquidDesignTokens.Spectral.mint
                                : LiquidDesignTokens.Spectral.amber
                        )
                        coachMetricCard(
                            value: "\(Int(report.interventionWinRate * 100))%",
                            label: "Recovery Rate",
                            color: report.interventionWinRate > 0.5
                                ? LiquidDesignTokens.Spectral.mint
                                : LiquidDesignTokens.Spectral.amber
                        )
                        coachMetricCard(
                            value: "\(report.avgSessionMinutes)m",
                            label: "Avg Session",
                            color: LiquidDesignTokens.Spectral.electricBlue
                        )
                    }

                    // Top triggers
                    if !report.topTriggers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            TrackedLabel(
                                text: "Top Distractions",
                                font: LiquidDesignTokens.Typography.labelSmall,
                                tracking: 1.5
                            )
                            ForEach(report.topTriggers.prefix(3), id: \.label) { trigger in
                                HStack(spacing: 8) {
                                    Image(systemName: trigger.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                                        .frame(width: 16)
                                    Text(trigger.label)
                                        .font(LiquidDesignTokens.Typography.bodySmall)
                                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                                    Spacer()
                                    Text("\(trigger.count) min")
                                        .font(LiquidDesignTokens.Typography.labelSmall)
                                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Coaching tip based on data
                    if let tip = coachingTip(from: report) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                                .padding(.top, 2)
                            Text(tip)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
        }
    }

    private func coachMetricCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(LiquidDesignTokens.Typography.labelSmall)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                        .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
                )
        }
    }

    private func buildCoachReport() -> FocusCoachWeeklyReport {
        let sessions = allSessions.filter { $0.type == .focus }.map { session in
            FocusCoachInsightsBuilder.SessionSnapshot(
                id: session.id,
                type: session.type.rawValue,
                duration: session.duration,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                completed: session.completed
            )
        }
        let appSnapshots = appUsageEntries.map { entry in
            FocusCoachInsightsBuilder.AppUsageSnapshot(
                appName: entry.appName,
                duringFocusSeconds: entry.duringFocusSeconds,
                category: entry.category.rawValue
            )
        }
        return FocusCoachInsightsBuilder().build(
            sessions: sessions,
            interruptions: [],
            attempts: [],
            appUsage: appSnapshots
        )
    }

    private func coachingTip(from report: FocusCoachWeeklyReport) -> String? {
        if report.completionRate < 0.5 {
            return "Try shorter sessions (15–20 min) to build momentum. Research shows completing shorter blocks builds self-efficacy (Steel, 2007)."
        }
        if report.interventionWinRate > 0 && report.interventionWinRate < 0.3 {
            return "Coach prompts aren't helping much yet. Consider adjusting prompt budget or try the \"Clean Restart\" action — structured re-engagement works better than willpower alone (Rozental, 2018)."
        }
        if !report.topTriggers.isEmpty {
            return "Your top distraction is \(report.topTriggers[0].label). Consider adding it to a block profile during focus sessions."
        }
        if report.completionRate > 0.85 {
            return "Strong completion rate! You're building consistent focus habits. Micro-breaks between sessions boost vigor and reduce fatigue (Albulescu, 2022)."
        }
        return nil
    }

    private struct BehavioralInsight {
        let icon: String
        let text: String
        let sentiment: Sentiment
        let color: Color

        enum Sentiment { case positive, neutral, warning }
    }

    private var behavioralInsights: [BehavioralInsight] {
        var insights = [BehavioralInsight]()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 1. Pause/break duration pattern
        let breaks = allSessions.filter { $0.type != .focus }
        if breaks.count >= 3 {
            let avgBreak = breaks.reduce(0.0) { $0 + $1.actualDuration } / Double(breaks.count)
            let longBreaks = breaks.filter { $0.actualDuration > avgBreak * 1.5 }.count
            let longBreakRatio = Double(longBreaks) / Double(breaks.count)

            if longBreakRatio > 0.4 {
                insights.append(BehavioralInsight(
                    icon: "hourglass.bottomhalf.filled",
                    text: "Your breaks tend to run long — \(Int(longBreakRatio * 100))% of your breaks exceed the average of \(Int(avgBreak / 60))m. Once you pause, you take extended breaks. Try setting a timer for breaks too.",
                    sentiment: .warning,
                    color: .orange
                ))
            } else if avgBreak < 180 {
                insights.append(BehavioralInsight(
                    icon: "bolt.fill",
                    text: "You take quick, efficient breaks — averaging just \(Int(avgBreak / 60))m. Your recovery style is sprint-like, keeping momentum high.",
                    sentiment: .positive,
                    color: .green
                ))
            }
        }

        // 2. Consistency analysis
        let last14Days = (0..<14).map { offset -> (Date, TimeInterval) in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let total = focusSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0.0) { $0 + $1.actualDuration }
            return (day, total)
        }
        let activeDays14 = last14Days.filter { $0.1 > 0 }.count
        let totalMinutes14 = last14Days.reduce(0.0) { $0 + $1.1 } / 60

        if activeDays14 >= 10 {
            insights.append(BehavioralInsight(
                icon: "flame.fill",
                text: "You've focused \(activeDays14) out of the last 14 days — that's excellent consistency. You've built \(Int(totalMinutes14))m of focus time. Keep this habit loop going.",
                sentiment: .positive,
                color: .orange
            ))
        } else if activeDays14 >= 5 && activeDays14 < 10 {
            insights.append(BehavioralInsight(
                icon: "chart.line.uptrend.xyaxis",
                text: "You focused \(activeDays14)/14 days recently. Your active days average \(activeDays14 > 0 ? Int(totalMinutes14 / Double(activeDays14)) : 0)m. Aim for at least 10 days to build a sustainable habit.",
                sentiment: .neutral,
                color: .blue
            ))
        }

        // 3. Focus momentum — once started, how long do you go?
        let completedSessions = focusSessions.filter(\.completed)
        let abandonedSessions = focusSessions.filter { !$0.completed }
        if completedSessions.count + abandonedSessions.count >= 5 {
            let completionRate = Double(completedSessions.count) / Double(completedSessions.count + abandonedSessions.count)
            if completionRate > 0.85 {
                insights.append(BehavioralInsight(
                    icon: "target",
                    text: "Once you start focusing, you finish — \(Int(completionRate * 100))% completion rate. You have strong focus momentum and rarely abandon sessions.",
                    sentiment: .positive,
                    color: .green
                ))
            } else if completionRate < 0.5 {
                insights.append(BehavioralInsight(
                    icon: "exclamationmark.triangle.fill",
                    text: "You complete \(Int(completionRate * 100))% of sessions. Consider shorter initial sessions — completing a 15m session builds confidence for longer ones.",
                    sentiment: .warning,
                    color: .red
                ))
            }
        }

        // 4. Performance trend comparison (this week vs last week)
        let thisWeekStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let lastWeekStart = calendar.date(byAdding: .day, value: -13, to: today)!
        let thisWeekMinutes = focusSessions.filter {
            $0.startedAt >= thisWeekStart
        }.reduce(0.0) { $0 + $1.actualDuration } / 60
        let lastWeekMinutes = focusSessions.filter {
            $0.startedAt >= lastWeekStart && $0.startedAt < thisWeekStart
        }.reduce(0.0) { $0 + $1.actualDuration } / 60

        if lastWeekMinutes > 0 {
            let change = ((thisWeekMinutes - lastWeekMinutes) / lastWeekMinutes) * 100
            if change > 15 {
                insights.append(BehavioralInsight(
                    icon: "arrow.up.right",
                    text: "Your productivity is up \(Int(change))% compared to last week — \(Int(thisWeekMinutes))m vs \(Int(lastWeekMinutes))m. You're building momentum.",
                    sentiment: .positive,
                    color: .green
                ))
            } else if change < -15 {
                insights.append(BehavioralInsight(
                    icon: "arrow.down.right",
                    text: "Focus time is down \(Int(abs(change)))% from last week — \(Int(thisWeekMinutes))m vs \(Int(lastWeekMinutes))m. A good time to set a small daily goal to get back on track.",
                    sentiment: .warning,
                    color: .orange
                ))
            } else {
                insights.append(BehavioralInsight(
                    icon: "equal.circle.fill",
                    text: "You're maintaining a steady pace — \(Int(thisWeekMinutes))m this week, similar to last week's \(Int(lastWeekMinutes))m. Consistency trumps intensity.",
                    sentiment: .neutral,
                    color: .blue
                ))
            }
        }

        // 5. Peak time personality
        let peakHour = hourlyData.max(by: { $0.totalMinutes < $1.totalMinutes })
        if let peak = peakHour, peak.totalMinutes > 30 {
            let personality: String
            if peak.hour < 10 {
                personality = "You're an early bird — your best work happens before 10am. Protect your mornings for deep work."
            } else if peak.hour < 14 {
                personality = "Your peak focus is midday (\(peak.label)). You hit flow state when the morning settles."
            } else if peak.hour < 18 {
                personality = "You're an afternoon focuser — \(peak.label) is your golden hour. Schedule creative work here."
            } else {
                personality = "You're a night owl — your deepest focus comes after 6pm. Embrace your natural rhythm."
            }
            insights.append(BehavioralInsight(
                icon: "clock.fill",
                text: personality,
                sentiment: .neutral,
                color: .purple
            ))
        }

        return Array(insights.prefix(5))
    }

    private func insightCard(_ insight: BehavioralInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(insight.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: insight.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(insight.color)
            }

            Text(insight.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(insight.color.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(insight.color.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - App Usage

    private var appUsageSection: some View {
        LiquidGlassPanel {
            DisclosureGroup(isExpanded: $showAppUsage) {
                appUsageContent
                    .padding(.top, 8)
            } label: {
                LiquidSectionHeader(
                    "App Usage",
                    subtitle: appUsageSummary
                )
            }
            .tint(.secondary)
            .padding(16)
        }
    }

    private var appUsageContent: some View {
        Group {
            let topApps = todayTopApps
            if topApps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("App tracking will appear as you use your Mac")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(topApps.enumerated()), id: \.offset) { _, app in
                        appUsageRow(app)
                    }
                }

                Divider()
                categoryBreakdown
            }
        }
    }

    private struct AppUsageSummaryItem {
        let name: String
        let bundleId: String
        let totalSeconds: Int
        let duringFocus: Int
        let category: AppUsageEntry.AppCategory
    }

    private var todayTopApps: [AppUsageSummaryItem] {
        let today = Calendar.current.startOfDay(for: Date())
        let todayEntries = appUsageEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }

        // Aggregate by app name
        var grouped = [String: (name: String, bundleId: String, total: Int, focus: Int, category: AppUsageEntry.AppCategory)]()
        for entry in todayEntries {
            let key = entry.bundleIdentifier
            if var existing = grouped[key] {
                existing.total += entry.totalSeconds
                existing.focus += entry.duringFocusSeconds
                grouped[key] = existing
            } else {
                grouped[key] = (entry.appName, entry.bundleIdentifier, entry.totalSeconds, entry.duringFocusSeconds, entry.category)
            }
        }

        return grouped.values
            .map { AppUsageSummaryItem(name: $0.name, bundleId: $0.bundleId, totalSeconds: $0.total, duringFocus: $0.focus, category: $0.category) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(8)
            .map { $0 }
    }

    private var appUsageSummary: String {
        let apps = todayTopApps
        guard !apps.isEmpty else { return "Tracking app usage throughout the day" }
        let totalMinutes = apps.reduce(0) { $0 + $1.totalSeconds } / 60
        return "\(apps.count) apps tracked · \(totalMinutes)m total today"
    }

    private func appUsageRow(_ app: AppUsageSummaryItem) -> some View {
        let maxSeconds = todayTopApps.first?.totalSeconds ?? 1

        return HStack(spacing: 10) {
            // Category indicator
            Circle()
                .fill(categoryColor(app.category))
                .frame(width: 8, height: 8)

            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.04))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(categoryColor(app.category).opacity(0.6))
                        .frame(width: max(2, geo.size.width * CGFloat(app.totalSeconds) / CGFloat(max(maxSeconds, 1))))
                }
            }
            .frame(height: 12)

            Text(formatDuration(app.totalSeconds))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(height: 24)
    }

    private var categoryBreakdown: some View {
        let apps = todayTopApps
        let productive = apps.filter { $0.category == .productive }.reduce(0) { $0 + $1.totalSeconds }
        let neutral = apps.filter { $0.category == .neutral }.reduce(0) { $0 + $1.totalSeconds }
        let distracting = apps.filter { $0.category == .distracting }.reduce(0) { $0 + $1.totalSeconds }
        let total = max(productive + neutral + distracting, 1)

        return VStack(alignment: .leading, spacing: 8) {
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    if productive > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.7))
                            .frame(width: geo.size.width * CGFloat(productive) / CGFloat(total))
                    }
                    if neutral > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(neutral) / CGFloat(total))
                    }
                    if distracting > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(distracting) / CGFloat(total))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            // Legend
            HStack(spacing: 16) {
                categoryLegend("Productive", color: .green, seconds: productive)
                categoryLegend("Neutral", color: .blue, seconds: neutral)
                categoryLegend("Distracting", color: .orange, seconds: distracting)
            }
        }
    }

    private func categoryLegend(_ label: String, color: Color, seconds: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6)
            Text("\(label) \(formatDuration(seconds))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func categoryColor(_ category: AppUsageEntry.AppCategory) -> Color {
        switch category {
        case .productive: .green
        case .neutral: .blue
        case .distracting: .orange
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h\(mins)m" }
        return "\(mins)m"
    }

    // MARK: - Analytics Grid (Peak Hours + Duration Distribution)

    private var analyticsGridSection: some View {
        LiquidGlassPanel {
            VStack(spacing: 16) {
                LiquidSectionHeader("Analytics", subtitle: "Hours and session patterns")

                HStack(alignment: .top, spacing: 16) {
                    peakHoursColumn
                    Divider()
                    durationDistributionColumn
                }
            }
            .padding(16)
        }
    }

    private var peakHoursColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Peak Hours")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(bestHourSummary)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)

            HStack(spacing: 1) {
                ForEach(hourlyData, id: \.hour) { item in
                    let intensity = item.totalMinutes / maxHourlyMinutes
                    let isSelected = selectedHour == item.hour

                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                intensity > 0 ?
                                LiquidDesignTokens.Spectral.primaryContainer.opacity(0.2 + intensity * 0.8) :
                                Color.white.opacity(0.04)
                            )
                            .frame(height: isSelected ? 30 : 22)
                            .overlay {
                                if isSelected && item.totalMinutes > 0 {
                                    Text("\(Int(item.totalMinutes))m")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                            }

                        Text(item.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? .primary : .tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedHour = selectedHour == item.hour ? nil : item.hour }
                    .accessibilityLabel("\(item.label), \(Int(item.totalMinutes)) minutes of focus")
                    .accessibilityAddTraits(.isButton)
                    .animation(FFMotion.control, value: isSelected)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var durationDistributionColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Lengths")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(averageDurationSummary)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)

            HStack(spacing: 3) {
                ForEach(durationBuckets, id: \.label) { bucket in
                    VStack(spacing: 4) {
                        Text("\(bucket.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(bucket.count > 0 ? .primary : .tertiary)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(bucketColor(bucket.index))
                            .frame(height: max(4, CGFloat(bucket.count) / CGFloat(maxBucketCount) * 60))

                        Text(bucket.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
        .frame(maxWidth: .infinity)
    }

    private struct HourData: Identifiable {
        let hour: Int
        let totalMinutes: Double
        var id: Int { hour }

        var label: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "ha"
            let date = Calendar.current.date(from: DateComponents(hour: hour))!
            return formatter.string(from: date).lowercased()
        }
    }

    private var hourlyData: [HourData] {
        var buckets = [Int: TimeInterval]()
        for session in focusSessions {
            let hour = Calendar.current.component(.hour, from: session.startedAt)
            buckets[hour, default: 0] += session.actualDuration
        }
        // Show hours 5am to midnight (typical productive range)
        return (5..<24).compactMap { hour in
            let minutes = (buckets[hour] ?? 0) / 60
            // Only show hours that have data or are in work hours (8-20)
            guard minutes > 0 || (hour >= 8 && hour <= 20) else { return nil }
            return HourData(hour: hour, totalMinutes: minutes)
        }
    }

    private var maxHourlyMinutes: Double {
        max(hourlyData.map(\.totalMinutes).max() ?? 1, 1)
    }

    private var bestHourSummary: String {
        guard let best = hourlyData.max(by: { $0.totalMinutes < $1.totalMinutes }),
              best.totalMinutes > 0 else {
            return "Complete sessions to reveal your peak hours"
        }
        return "Your peak is \(best.label) · \(Int(best.totalMinutes))m total"
    }

    // MARK: - Duration Distribution Data

    private struct DurationBucket {
        let label: String
        let count: Int
        let index: Int
    }

    private var durationBuckets: [DurationBucket] {
        let ranges: [(String, (TimeInterval, TimeInterval))] = [
            ("<10m", (0, 600)),
            ("10-20m", (600, 1200)),
            ("20-30m", (1200, 1800)),
            ("30-45m", (1800, 2700)),
            ("45-60m", (2700, 3600)),
            ("60m+", (3600, .infinity))
        ]
        return ranges.enumerated().map { idx, range in
            let count = focusSessions.filter { d in
                let dur = d.actualDuration
                return dur >= range.1.0 && dur < range.1.1
            }.count
            return DurationBucket(label: range.0, count: count, index: idx)
        }
    }

    private var maxBucketCount: Int {
        max(durationBuckets.map(\.count).max() ?? 1, 1)
    }

    private var averageDurationSummary: String {
        guard !focusSessions.isEmpty else { return "No sessions yet" }
        let avg = focusSessions.reduce(0.0) { $0 + $1.actualDuration } / Double(focusSessions.count)
        return "Average session: \(Int(avg / 60))m across \(focusSessions.count) sessions"
    }

    private func bucketColor(_ index: Int) -> Color {
        let colors: [Color] = [
            Color(hex: 0x3E90FF).opacity(0.3),
            Color(hex: 0x3E90FF).opacity(0.45),
            Color(hex: 0x3E90FF).opacity(0.6),
            Color(hex: 0x3E90FF).opacity(0.7),
            Color(hex: 0x3E90FF).opacity(0.8),
            Color(hex: 0x3E90FF).opacity(0.9)
        ]
        return colors[min(index, colors.count - 1)]
    }

    // MARK: - Break Behavior Data (rendered inside trends section)

    private var totalBreaks: Int {
        allSessions.filter { $0.type != .focus }.count
    }

    private var averageBreakLength: String {
        let breaks = allSessions.filter { $0.type != .focus }
        guard !breaks.isEmpty else { return "—" }
        let avg = breaks.reduce(0.0) { $0 + $1.actualDuration } / Double(breaks.count)
        return "\(Int(avg / 60))m"
    }

    private var breakRate: String {
        let totalFocusSessions = focusSessions.filter(\.completed).count
        guard totalFocusSessions > 0 else { return "—" }
        let ratio = Double(totalBreaks) / Double(totalFocusSessions)
        return String(format: "%.0f%%", ratio * 100)
    }

    private var breakRateSubtitle: String {
        totalBreaks > 0 ? "Breaks/sessions" : "No data"
    }

    private var bestDay: TimeInterval {
        let calendar = Calendar.current
        var dailyTotals = [Date: TimeInterval]()
        for session in focusSessions {
            let day = calendar.startOfDay(for: session.startedAt)
            dailyTotals[day, default: 0] += session.actualDuration
        }
        return dailyTotals.values.max() ?? 0
    }

    private var bestDayLabel: String {
        let calendar = Calendar.current
        var dailyTotals = [Date: TimeInterval]()
        for session in focusSessions {
            let day = calendar.startOfDay(for: session.startedAt)
            dailyTotals[day, default: 0] += session.actualDuration
        }
        guard let best = dailyTotals.max(by: { $0.value < $1.value }) else { return "" }
        return best.key.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Trends + Breaks (merged)

    private var trendsAndBreaksSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "30-Day Trend",
                    subtitle: trendSummary
                )

                SparklineView(data: last30DaysData)
                    .frame(height: 60)

                Divider()

                HStack(spacing: 12) {
                    StatCard(
                        title: "Avg Break",
                        value: averageBreakLength,
                        icon: "cup.and.saucer.fill",
                        color: .green,
                        subtitle: totalBreaks > 0 ? "\(totalBreaks) breaks" : nil
                    )
                    StatCard(
                        title: "Break Rate",
                        value: breakRate,
                        icon: "arrow.triangle.branch",
                        color: .teal,
                        subtitle: breakRateSubtitle
                    )
                    StatCard(
                        title: "Best Day",
                        value: bestDay.formattedFocusTime,
                        icon: "star.fill",
                        color: .yellow,
                        subtitle: bestDayLabel
                    )
                }
                .accessibilityElement(children: .combine)
            }
            .padding(16)
        }
    }

    private var last30DaysData: [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<30).map { offset in
            let day = calendar.date(byAdding: .day, value: -(29 - offset), to: today)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            return focusSessions.reduce(0.0) { sum, session in
                let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
                guard sessionEnd > day && session.startedAt < nextDay else { return sum }
                let overlapStart = max(session.startedAt, day)
                let overlapEnd = min(sessionEnd, nextDay)
                return sum + max(0, overlapEnd.timeIntervalSince(overlapStart))
            }
        }
    }

    private var trendSummary: String {
        let data = last30DaysData
        let firstHalf = data.prefix(15).reduce(0, +)
        let secondHalf = data.suffix(15).reduce(0, +)
        guard firstHalf > 0 else {
            return secondHalf > 0 ? "Getting started — keep building the habit!" : "No data yet"
        }
        let change = ((secondHalf - firstHalf) / firstHalf) * 100
        if change > 10 {
            return "Trending up \(Int(change))% — great momentum!"
        } else if change < -10 {
            return "Down \(Int(abs(change)))% from earlier — a fresh start awaits"
        }
        return "Steady pace — consistency is key"
    }

    // MARK: - Science Tips

    private var scienceTipsSection: some View {
        LiquidGlassPanel {
            DisclosureGroup(isExpanded: $showScienceTips) {
                VStack(spacing: 10) {
                    ForEach(contextualTips, id: \.title) { tip in
                        scienceTipCard(tip)
                    }
                }
                .padding(.top, 8)
            } label: {
                LiquidSectionHeader(
                    "Focus Science",
                    subtitle: "Research-backed tips for your patterns"
                )
            }
            .tint(.secondary)
            .padding(16)
        }
    }

    private struct ScienceTip {
        let icon: String
        let title: String
        let body: String
        let color: Color
    }

    private var contextualTips: [ScienceTip] {
        var tips = [ScienceTip]()

        // Tip based on average session length
        let avgDuration = focusSessions.isEmpty ? 0 : focusSessions.reduce(0.0) { $0 + $1.actualDuration } / Double(focusSessions.count)
        if avgDuration > 0 && avgDuration < 1500 {
            tips.append(ScienceTip(
                icon: "timer",
                title: "Build Up Gradually",
                body: "Your avg session is \(Int(avgDuration/60))m. Research shows working up to 25–50 min sessions maximizes deep work capacity.",
                color: .blue
            ))
        } else if avgDuration >= 2700 {
            tips.append(ScienceTip(
                icon: "brain",
                title: "Long Sessions Champion",
                body: "Sessions over 45m can deplete cognitive resources. Consider splitting into focused sprints with short breaks.",
                color: .purple
            ))
        }

        // Tip based on break behavior
        let breakTakenRatio = focusSessions.isEmpty ? 0 : Double(totalBreaks) / Double(focusSessions.count)
        if breakTakenRatio < 0.5 && focusSessions.count > 3 {
            tips.append(ScienceTip(
                icon: "cup.and.saucer.fill",
                title: "Take More Breaks",
                body: "You skip breaks often. The Pomodoro Technique works best with regular rest — it prevents mental fatigue and boosts creativity.",
                color: .green
            ))
        }

        // Tip based on consistency
        let activeDaysLast7 = last30DaysData.suffix(7).filter { $0 > 0 }.count
        if activeDaysLast7 >= 5 {
            tips.append(ScienceTip(
                icon: "flame.fill",
                title: "Consistency Superstar",
                body: "You've focused \(activeDaysLast7)/7 days this week. Consistency matters more than intensity for building lasting habits.",
                color: .orange
            ))
        } else if activeDaysLast7 <= 2 && focusSessions.count > 5 {
            tips.append(ScienceTip(
                icon: "calendar.badge.exclamationmark",
                title: "Build the Habit",
                body: "Try to focus at least 4 days a week. Even a single short session maintains your habit loop.",
                color: .red
            ))
        }

        // Always include a general tip if we have few contextual ones
        if tips.count < 2 {
            tips.append(ScienceTip(
                icon: "lightbulb.fill",
                title: "The 2-Minute Rule",
                body: "If you're procrastinating, commit to just 2 minutes of work. Starting is the hardest part — momentum follows.",
                color: .yellow
            ))
        }

        return Array(tips.prefix(3))
    }

    private func scienceTipCard(_ tip: ScienceTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tip.color)
                .frame(width: 28, height: 28)
                .background(tip.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(tip.body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Sparkline

private struct SparklineView: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(data.max() ?? 1, 1)
            let points = data.enumerated().map { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(max(data.count - 1, 1)),
                    y: geo.size.height * (1 - CGFloat(value / maxVal))
                )
            }

            ZStack {
                // Fill area
                Path { path in
                    guard !points.isEmpty else { return }
                    path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                    path.addLine(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            LiquidDesignTokens.Spectral.primaryContainer.opacity(0.2),
                            LiquidDesignTokens.Spectral.primaryContainer.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line
                Path { path in
                    guard !points.isEmpty else { return }
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            LiquidDesignTokens.Spectral.primaryContainer,
                            LiquidDesignTokens.Spectral.electricBlue
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                // End dot
                if let lastPoint = points.last {
                    Circle()
                        .fill(LiquidDesignTokens.Spectral.electricBlue)
                        .frame(width: 6, height: 6)
                        .position(lastPoint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("30-day focus trend, ranging from \(Int((data.min() ?? 0) / 60)) to \(Int((data.max() ?? 0) / 60)) minutes per day")
    }
}
