import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(sort: \AppUsageEntry.date) private var appUsageEntries: [AppUsageEntry]
    @Query(sort: \CoachInterruption.detectedAt) private var coachInterruptions: [CoachInterruption]
    @Query(sort: \InterventionAttempt.deliveredAt) private var coachAttempts: [InterventionAttempt]
    @Query(sort: \TaskIntent.createdAt) private var taskIntents: [TaskIntent]
    private let analyticsSnapshotNow = Date()
    @State private var selectedHour: Int? = nil
    @State private var showAllInsights = false
    @State private var showScienceTips = false
    @State private var showAppUsage = false
    @Environment(\.focusFlowEvidenceRendering) private var isEvidenceRendering
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dailyGoal: TimeInterval {
        allSettings.first?.dailyFocusGoal ?? 7200
    }

    private var shouldExposeRawDomains: Bool {
        allSettings.first?.coachCollectRawDomains == true
    }

    private var visibleAppUsageEntries: [AppUsageEntry] {
        InsightsAppUsagePolicy.visibleEntries(
            from: appUsageEntries,
            collectRawDomains: shouldExposeRawDomains
        )
    }

    private var analyticsReport: CompanionAnalyticsReport {
        CompanionAnalyticsBuilder().build(
            entries: visibleAppUsageEntries,
            domainTrackingEnabled: shouldExposeRawDomains,
            now: analyticsSnapshotNow
        )
    }

    private var coachReportWindow: DateInterval {
        let calendar = Calendar.current
        return InsightsWindowing.trailing7DayInterval(relativeTo: analyticsSnapshotNow, calendar: calendar)
            ?? DateInterval(start: analyticsSnapshotNow, end: analyticsSnapshotNow)
    }

    private var previousCoachReportWindow: DateInterval {
        let calendar = Calendar.current
        return InsightsWindowing.previousInterval(before: coachReportWindow, calendar: calendar)
            ?? DateInterval(start: coachReportWindow.start, end: coachReportWindow.start)
    }

    private var coachWindowSessions: [FocusSession] {
        InsightsWindowing.overlappingFocusSessions(allSessions, in: coachReportWindow)
    }

    private var previousCoachWindowSessions: [FocusSession] {
        InsightsWindowing.overlappingFocusSessions(allSessions, in: previousCoachReportWindow)
    }

    private var coachWindowInterruptions: [CoachInterruption] {
        coachInterruptions.filter { coachReportWindow.contains($0.detectedAt) }
    }

    private var coachWindowAttempts: [InterventionAttempt] {
        coachAttempts.filter { coachReportWindow.contains($0.deliveredAt) }
    }

    private var coachWindowTaskIntents: [TaskIntent] {
        let currentSessionIDs = Set(coachWindowSessions.map(\.id))
        return taskIntents.filter { intent in
            if let sessionId = intent.sessionId {
                return currentSessionIDs.contains(sessionId)
            }
            return coachReportWindow.contains(intent.createdAt)
        }
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
                guardianRecommendationsSection
                analyticsGridSection
                trendsAndBreaksSection
                scienceTipsSection
                appUsageSection
            }
            .padding(24)
        }
        .background(.clear)
        .animation(reduceMotion ? nil : FFMotion.section, value: selectedHour)
        .onAppear {
            if isEvidenceRendering {
                showAppUsage = true
            }
        }
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
                            .animation(reduceMotion ? nil : .spring(response: 1.0, dampingFraction: 0.8), value: focusScore)

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
                            .accessibilityHidden(true)
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
        case 80...100: "SUSTAINED"
        case 50..<80: "EMERGING"
        case 30..<50: "FRAGILE"
        default: "BOOTSTRAP"
        }
    }

    private var focusScoreSummary: String {
        switch focusScore {
        case 80...100: "You are sustaining deep-work volume and consistency."
        case 50..<80: "You are showing regular starts with moderate session depth."
        case 30..<50: "Your pattern is active but shallow; depth is the bottleneck."
        default: "Data is early — use consistent starts to stabilize your baseline."
        }
    }

    private func calculateConsistency() -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: analyticsSnapshotNow)
        let daysWithSessions = (0..<7).filter { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return focusSessions.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
        }.count
        return Double(daysWithSessions) / 7.0
    }

    private func calculateCompletionRate() -> Double {
        InsightsWindowing.completionRate(for: focusSessions, in: coachReportWindow)
    }

    private func calculateGoalAdherence() -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: analyticsSnapshotNow)
        let goal = dailyGoal
        let daysMetGoal = (0..<7).filter { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            let dayTotal = focusSessions
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0.0) { $0 + $1.actualDuration }
            return dayTotal >= goal
        }.count
        return Double(daysMetGoal) / 7.0
    }

    // MARK: - Guardian Recommendations

    private var guardianRecommendationsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader(
                    "Guardian Recommendations",
                    subtitle: "Data-driven block candidates from your last 7 days"
                )

                if guardianRecommendations.isEmpty {
                    Text("No high-confidence block recommendations in the last 7 days yet. Keep using FocusFlow and classify drift honestly to train guardian intelligence.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(guardianRecommendations.enumerated()), id: \.offset) { _, rec in
                        HStack(spacing: 10) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                                .frame(width: 18)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.target)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(rec.reason)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Text("\(Int(rec.confidence * 100))%")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(LiquidDesignTokens.Spectral.electricBlue.opacity(0.12))
                                )
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }
            }
            .padding(16)
        }
    }

    private struct GuardianRecommendation {
        let target: String
        let confidence: Double
        let reason: String
    }

    private var guardianRecommendations: [GuardianRecommendation] {
        let recent = analyticsReport.trailing7Days.rows
        guard !recent.isEmpty else { return [] }

        var grouped = [String: (focus: Int, outside: Int)]()

        for entry in recent {
            guard let target = AppUsageEntry.recommendedBlockTarget(
                bundleIdentifier: entry.bundleIdentifier,
                appName: entry.label
            ) else { continue }
            var state = grouped[target, default: (focus: 0, outside: 0)]
            state.focus += entry.duringFocusSeconds
            state.outside += entry.outsideFocusSeconds
            grouped[target] = state
        }

        let lowPriorityWeight = Double(
            coachWindowAttempts.filter { $0.skipReasonRaw == FocusCoachSkipReason.lowPriorityWork.rawValue }.count
        )

        return grouped.compactMap { target, totals in
            let weightedSeconds = Double(totals.focus) * 1.6 + Double(totals.outside)
            guard weightedSeconds >= 900 else { return nil }
            // Saturation at 36 000 weighted-seconds (~10 h / 7 days) gives heavy-use apps
            // high scores; light-use apps land 50–65%. Old 7 200s cap made everything 87%.
            let confidence = min(0.97, 0.50 + min(0.40, weightedSeconds / 36_000.0) + min(0.07, lowPriorityWeight * 0.02))
            let focusMinutes = totals.focus / 60
            let outsideMinutes = totals.outside / 60
            let displayTarget = AppUsageEntry.recommendationDisplayLabel(for: target)
            return GuardianRecommendation(
                target: displayTarget,
                confidence: confidence,
                reason: "\(focusMinutes)m during focus, \(outsideMinutes)m outside focus in the last 7 days."
            )
        }
        .sorted { $0.confidence > $1.confidence }
        .prefix(5)
        .map { $0 }
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
                                    .accessibilityHidden(true)
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
                    subtitle: "Science-based coaching from your last 7 days"
                )

                let report = buildCoachReport()

                if report.totalSessions < 3 {
                    coachEmptyState
                } else {
                    coachHeroMetrics(report: report)
                    coachRecoveryFunnel(report: report)
                    coachCalibration(report: report)
                    coachTrendIndicator(report: report)
                    coachRecoverySpeed(report: report)
                    coachBestSessionByType(report: report)
                    coachInterventionEffectiveness
                    coachTopTriggers(report: report)
                    coachReasonBreakdown
                    coachNextBestExperiment(report: report)
                    coachPersonalizedTips(report: report)
                }
            }
            .padding(16)
        }
    }

    private var coachEmptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("Complete 3+ focus sessions in the last 7 days to unlock personalized coaching insights")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)
            Spacer()
        }
    }

    @ViewBuilder
    private func coachHeroMetrics(report: FocusCoachWeeklyReport) -> some View {
        let hasInterventionData = !coachWindowAttempts.isEmpty
        HStack(spacing: 12) {
            coachMetricCard(
                value: "\(Int(report.completionRate * 100))%",
                label: "Completion",
                color: report.completionRate > 0.7
                    ? LiquidDesignTokens.Spectral.mint
                    : LiquidDesignTokens.Spectral.amber
            )
            if hasInterventionData {
                coachMetricCard(
                    value: "\(Int(report.interventionWinRate * 100))%",
                    label: "Recovery",
                    color: report.interventionWinRate > 0.5
                        ? LiquidDesignTokens.Spectral.mint
                        : LiquidDesignTokens.Spectral.amber
                )
            } else {
                coachMetricCard(
                    value: "\(report.totalSessions)",
                    label: "Sessions",
                    color: LiquidDesignTokens.Spectral.electricBlue
                )
            }
            coachMetricCard(
                value: "\(report.avgSessionMinutes)m",
                label: "Avg Session",
                color: LiquidDesignTokens.Spectral.electricBlue
            )
        }
    }

    @ViewBuilder
    private func coachTrendIndicator(report: FocusCoachWeeklyReport) -> some View {
        if let trend = report.weekOverWeekTrend {
            HStack(spacing: 6) {
                Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(trend >= 0 ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.salmon)
                    .accessibilityHidden(true)
                Text(trend >= 0
                    ? "Completion up \(Int(trend * 100))% vs last week"
                    : "Completion down \(Int(abs(trend) * 100))% vs last week"
                )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                    .fill((trend >= 0 ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.salmon).opacity(0.06))
            )
        }
    }

    @ViewBuilder
    private func coachRecoverySpeed(report: FocusCoachWeeklyReport) -> some View {
        if report.recoverySpeedSeconds > 0 {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text("Avg recovery time:")
                    .font(LiquidDesignTokens.Typography.bodySmall)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                Text(formatRecoverySpeed(report.recoverySpeedSeconds))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(report.recoverySpeedSeconds < 60
                        ? LiquidDesignTokens.Spectral.mint
                        : LiquidDesignTokens.Spectral.amber
                    )
                    .monospacedDigit()
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func coachRecoveryFunnel(report: FocusCoachWeeklyReport) -> some View {
        if report.recoveryFunnel.prompted > 0 {
            VStack(alignment: .leading, spacing: 6) {
                TrackedLabel(
                    text: "Recovery Funnel",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )
                HStack(spacing: 10) {
                    funnelPill(
                        title: "Prompted",
                        value: "\(report.recoveryFunnel.prompted)",
                        color: LiquidDesignTokens.Spectral.electricBlue
                    )
                    funnelPill(
                        title: "Acted",
                        value: "\(report.recoveryFunnel.acted)",
                        color: LiquidDesignTokens.Spectral.amber
                    )
                    funnelPill(
                        title: "Recovered <2m",
                        value: "\(report.recoveryFunnel.recoveredWithin2Minutes)",
                        color: LiquidDesignTokens.Spectral.mint
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func coachCalibration(report: FocusCoachWeeklyReport) -> some View {
        let calibration = report.confidenceCalibration
        let hasData = calibration.highRiskAttempts + calibration.lowRiskAttempts > 0
        if hasData {
            let highRate = calibration.highRiskAttempts > 0
                ? Double(calibration.highRiskRecovered) / Double(calibration.highRiskAttempts)
                : 0
            let lowRate = calibration.lowRiskAttempts > 0
                ? Double(calibration.lowRiskRecovered) / Double(calibration.lowRiskAttempts)
                : 0

            VStack(alignment: .leading, spacing: 6) {
                TrackedLabel(
                    text: "Confidence Calibration",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )

                HStack(spacing: 8) {
                    Label("High risk: \(Int(highRate * 100))% recovery (\(calibration.highRiskRecovered)/\(calibration.highRiskAttempts))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Label("Lower risk: \(Int(lowRate * 100))% recovery (\(calibration.lowRiskRecovered)/\(calibration.lowRiskAttempts))",
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func coachNextBestExperiment(report: FocusCoachWeeklyReport) -> some View {
        if let experiment = report.nextBestExperiment, !experiment.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                TrackedLabel(
                    text: "Next Best Experiment",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(experiment)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                        .fill(LiquidDesignTokens.Spectral.amber.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                                .strokeBorder(LiquidDesignTokens.Spectral.amber.opacity(0.2), lineWidth: 0.5)
                        )
                )
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func coachBestSessionByType(report: FocusCoachWeeklyReport) -> some View {
        if !report.bestSessionLengthByTaskType.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                TrackedLabel(
                    text: "Optimal Session Length",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )
                ForEach(Array(report.bestSessionLengthByTaskType.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { taskType in
                    if let minutes = report.bestSessionLengthByTaskType[taskType] {
                        HStack(spacing: 8) {
                            Image(systemName: taskType.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(taskType.displayName)
                                .font(LiquidDesignTokens.Typography.bodySmall)
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                            Spacer()
                            Text("\(minutes) min")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var coachInterventionEffectiveness: some View {
        let attemptSnapshots = coachWindowAttempts.map {
            FocusCoachInsightsBuilder.AttemptSnapshot(
                kind: $0.kind,
                outcome: $0.outcome,
                riskScore: $0.riskScore,
                deliveredAt: $0.deliveredAt,
                resolvedAt: $0.resolvedAt
            )
        }
        let effectiveness = FocusCoachInsightsBuilder().interventionEffectiveness(attempts: attemptSnapshots)
        if !effectiveness.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                TrackedLabel(
                    text: "Intervention Effectiveness",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )
                ForEach(effectiveness, id: \.kind) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.kind == .quickPrompt ? "hand.tap.fill" : "exclamationmark.bubble.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(item.winRate > 0.5 ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.amber)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(item.kind == .quickPrompt ? "Quick Prompts" : item.kind == .strongPrompt ? "Strong Prompts" : "Nudges")
                            .font(LiquidDesignTokens.Typography.bodySmall)
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                        Spacer()
                        Text("\(Int(item.winRate * 100))% effective")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(item.winRate > 0.5 ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.amber)
                        Text("(\(item.improvedCount)/\(item.totalCount))")
                            .font(.system(size: 10))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func coachTopTriggers(report: FocusCoachWeeklyReport) -> some View {
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
                            .accessibilityHidden(true)
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
    }

    @ViewBuilder
    private var coachReasonBreakdown: some View {
        let reasonCounts = buildReasonBreakdown()
        if !reasonCounts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                TrackedLabel(
                    text: "Self-Reported Reasons",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )
                ForEach(reasonCounts, id: \.reason) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.reason.isLegitimate ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(item.reason.isLegitimate
                                ? LiquidDesignTokens.Spectral.mint
                                : LiquidDesignTokens.Spectral.amber)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(item.reason.displayName)
                            .font(LiquidDesignTokens.Typography.bodySmall)
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                        Spacer()
                        Text("\(item.count)×")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func coachPersonalizedTips(report: FocusCoachWeeklyReport) -> some View {
        let tips = allCoachingTips(from: report)
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TrackedLabel(
                    text: "Personalized Coaching",
                    font: LiquidDesignTokens.Typography.labelSmall,
                    tracking: 1.5
                )
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(tip)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    }
                }
            }
            .padding(.top, 4)
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

    private func funnelPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                        .strokeBorder(color.opacity(0.16), lineWidth: 0.5)
                )
        )
    }

    private func buildCoachReport() -> FocusCoachWeeklyReport {
        let sessions = coachWindowSessions.map { session in
            FocusCoachInsightsBuilder.SessionSnapshot(
                id: session.id,
                type: session.type.rawValue,
                duration: session.duration,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                completed: session.completed
            )
        }
        let prevSessions = previousCoachWindowSessions.map { session in
            FocusCoachInsightsBuilder.SessionSnapshot(
                id: session.id,
                type: session.type.rawValue,
                duration: session.duration,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                completed: session.completed
            )
        }
        let interruptions = coachWindowInterruptions.map {
            FocusCoachInsightsBuilder.InterruptionSnapshot(
                kind: $0.kind,
                reason: $0.reason,
                isLegitimate: $0.isLegitimate,
                detectedAt: $0.detectedAt
            )
        }
        let attempts = coachWindowAttempts.map {
            FocusCoachInsightsBuilder.AttemptSnapshot(
                kind: $0.kind,
                outcome: $0.outcome,
                riskScore: $0.riskScore,
                deliveredAt: $0.deliveredAt,
                resolvedAt: $0.resolvedAt
            )
        }
        let appSnapshots = analyticsReport.trailing7Days.rows.map { entry in
            FocusCoachInsightsBuilder.AppUsageSnapshot(
                appName: entry.label,
                duringFocusSeconds: entry.duringFocusSeconds,
                category: entry.category.rawValue
            )
        }
        let intentSnapshots = coachWindowTaskIntents.map {
            FocusCoachInsightsBuilder.TaskIntentSnapshot(
                sessionId: $0.sessionId,
                taskType: $0.taskType
            )
        }
        return FocusCoachInsightsBuilder().build(
            sessions: sessions,
            interruptions: interruptions,
            attempts: attempts,
            appUsage: appSnapshots,
            taskIntents: intentSnapshots,
            previousWeekSessions: prevSessions
        )
    }

    private func allCoachingTips(from report: FocusCoachWeeklyReport) -> [String] {
        var tips: [String] = []
        if report.completionRate < 0.5 {
            tips.append("Completion is below 50%. Shorten planned blocks to 15–20m for the next week; higher completion strengthens self-efficacy (Steel, 2007).")
        }
            if report.interventionWinRate > 0 && report.interventionWinRate < 0.3 {
                tips.append("Coach prompts aren't helping much yet. Consider adjusting prompt budget or try the \"Clean Restart\" action — structured re-engagement works better than willpower alone (Rozental, 2018).")
            }
        if !report.topTriggers.isEmpty {
            tips.append("Your top distraction is \(report.topTriggers[0].label). Consider adding it to a block profile during focus sessions.")
        }
        if report.completionRate > 0.85 {
            tips.append("Completion exceeds 85%. Keep break structure explicit; micro-breaks preserve vigor and reduce fatigue (Albulescu, 2022).")
        }
            if report.recoverySpeedSeconds > 120 {
                tips.append("Your avg recovery takes \(formatRecoverySpeed(report.recoverySpeedSeconds)). Practicing mental contrasting (MCII) before sessions can reduce drift response time (Wang, 2021).")
            }
            if report.recoveryFunnel.prompted >= 6 {
                let actedRate = Double(report.recoveryFunnel.acted) / Double(max(report.recoveryFunnel.prompted, 1))
                if actedRate < 0.35 {
                    tips.append("Only \(Int(actedRate * 100))% of prompts convert to action. Reduce noise by lowering prompt budget and relying on strong prompts for high-risk windows only.")
                }
                let fastRecoveryRate = report.recoveryFunnel.acted > 0
                    ? Double(report.recoveryFunnel.recoveredWithin2Minutes) / Double(report.recoveryFunnel.acted)
                    : 0
                if fastRecoveryRate < 0.4 {
                    tips.append("Recovery is slow after acting (\(Int(fastRecoveryRate * 100))% within 2 min). Try 5m restart as default response to rebuild momentum faster.")
                }
            }
            if let trend = report.weekOverWeekTrend, trend < -0.1 {
                tips.append("Completion dropped this week. Consider reviewing your session length — shorter focused blocks may help rebuild consistency.")
        }
        // Resistance-aware tip
        let highResistanceIntents = coachWindowTaskIntents.filter { $0.expectedResistance >= 4 }
        if highResistanceIntents.count >= 3 {
            tips.append("You frequently report high resistance. Try pairing difficult tasks with 'implementation intentions': specify exactly when, where, and how you'll start (Gollwitzer, 1999).")
        }
        let legitimateRatio = report.legitimateInterruptionRatio
        if legitimateRatio > 0.7 && report.totalInterruptions >= 3 {
            tips.append("Most of your interruptions are legitimate. Consider scheduling focus blocks when meetings and obligations are unlikely.")
        }
        return tips
    }

    private func formatRecoverySpeed(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
    }

    private struct ReasonCount: Sendable {
        let reason: FocusCoachReason
        let count: Int
    }

    private func buildReasonBreakdown() -> [ReasonCount] {
        var counts: [FocusCoachReason: Int] = [:]
        for interruption in coachWindowInterruptions {
            if let reason = interruption.reason {
                counts[reason, default: 0] += 1
            }
        }
        return counts.map { ReasonCount(reason: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
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
        let today = calendar.startOfDay(for: analyticsSnapshotNow)
        let coachCompletionSessions = coachWindowSessions

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
            }
        }

        // 2. Consistency analysis — quality-gated (not just showing up)
        let last14Days = (0..<14).compactMap { offset -> (Date, TimeInterval)? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let total = focusSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0.0) { $0 + $1.actualDuration }
            return (day, total)
        }
        let activeDays14 = last14Days.filter { $0.1 > 0 }.count
        let totalMinutes14 = last14Days.reduce(0.0) { $0 + $1.1 } / 60
        let avgMinPerDay14 = activeDays14 > 0 ? Int(totalMinutes14 / Double(activeDays14)) : 0

        if activeDays14 >= 10 && avgMinPerDay14 >= 25 {
            insights.append(BehavioralInsight(
                icon: "flame.fill",
                text: "Focused \(activeDays14)/14 days averaging \(avgMinPerDay14)m per day — strong volume and consistency. This regularity builds automatic focus habits (Rozental, 2018).",
                sentiment: .positive,
                color: .orange
            ))
        } else if activeDays14 >= 10 && avgMinPerDay14 < 25 {
            insights.append(BehavioralInsight(
                icon: "chart.line.uptrend.xyaxis",
                text: "You show up \(activeDays14)/14 days — great frequency. But averaging only \(avgMinPerDay14)m per day limits deep work. Try one 25m+ session daily to cross the flow threshold.",
                sentiment: .neutral,
                color: .blue
            ))
        } else if activeDays14 >= 5 && activeDays14 < 10 {
            insights.append(BehavioralInsight(
                icon: "chart.line.uptrend.xyaxis",
                text: "Focused \(activeDays14)/14 days, averaging \(avgMinPerDay14)m on active days. \(totalMinutes14 < 120 ? "Your total of \(Int(totalMinutes14))m is below the weekly deep work minimum of 2 hours." : "Building toward a sustainable habit — aim for 10+ days.")",
                sentiment: .neutral,
                color: .blue
            ))
        }

        // 3. Focus momentum — once started, how long do you go?
        let completedSessions = coachCompletionSessions.filter(\.completed)
        let abandonedSessions = coachCompletionSessions.filter { !$0.completed }
        if completedSessions.count + abandonedSessions.count >= 5 {
            let completionRate = Double(completedSessions.count) / Double(completedSessions.count + abandonedSessions.count)
            let avgCompletedMin = completedSessions.isEmpty ? 0 : Int(completedSessions.reduce(0.0) { $0 + $1.actualDuration } / Double(completedSessions.count) / 60)
            let avgAbandonedMin = abandonedSessions.isEmpty ? 0 : Int(abandonedSessions.reduce(0.0) { $0 + $1.actualDuration } / Double(abandonedSessions.count) / 60)
            if completionRate > 0.85 && avgCompletedMin >= 20 {
                insights.append(BehavioralInsight(
                    icon: "target",
                    text: "\(Int(completionRate * 100))% completion, averaging \(avgCompletedMin)m per session. Strong follow-through — your starting friction is your only bottleneck.",
                    sentiment: .positive,
                    color: .green
                ))
            } else if completionRate > 0.85 && avgCompletedMin < 20 {
                insights.append(BehavioralInsight(
                    icon: "target",
                    text: "High completion (\(Int(completionRate * 100))%) but sessions average only \(avgCompletedMin)m. You're good at finishing — try extending duration to unlock deeper focus.",
                    sentiment: .neutral,
                    color: .blue
                ))
            } else if completionRate < 0.5 {
                insights.append(BehavioralInsight(
                    icon: "exclamationmark.triangle.fill",
                    text: "Only \(Int(completionRate * 100))% completion rate. Abandoned sessions average \(avgAbandonedMin)m. Try setting your timer to \(max(5, avgAbandonedMin - 5))m — completing short sessions builds momentum (Steel, 2007).",
                    sentiment: .warning,
                    color: .red
                ))
            }
        }

        // 4. Performance trend comparison (this week vs last week) — actionable
        guard let thisWeekStart = calendar.date(byAdding: .day, value: -6, to: today),
              let lastWeekStart = calendar.date(byAdding: .day, value: -13, to: today) else { return insights }
        let thisWeekSessions = focusSessions.filter { $0.startedAt >= thisWeekStart }
        let thisWeekMinutes = thisWeekSessions.reduce(0.0) { $0 + $1.actualDuration } / 60
        let lastWeekMinutes = focusSessions.filter {
            $0.startedAt >= lastWeekStart && $0.startedAt < thisWeekStart
        }.reduce(0.0) { $0 + $1.actualDuration } / 60

        if lastWeekMinutes > 0 {
            let change = ((thisWeekMinutes - lastWeekMinutes) / lastWeekMinutes) * 100
            let avgSessionThis = thisWeekSessions.isEmpty ? 0 : Int(thisWeekMinutes / Double(thisWeekSessions.count))
            if change > 15 {
                insights.append(BehavioralInsight(
                    icon: "arrow.up.right",
                    text: "Up \(Int(change))% vs last week (\(Int(thisWeekMinutes))m vs \(Int(lastWeekMinutes))m). \(thisWeekSessions.count) sessions averaging \(avgSessionThis)m each.",
                    sentiment: .positive,
                    color: .green
                ))
            } else if change < -15 {
                let deficit = Int(lastWeekMinutes - thisWeekMinutes)
                insights.append(BehavioralInsight(
                    icon: "arrow.down.right",
                    text: "Down \(Int(abs(change)))% from last week (\(Int(thisWeekMinutes))m vs \(Int(lastWeekMinutes))m). You need ~\(deficit)m more this week to match. That's \(deficit / max(1, 7 - last14Days.prefix(7).filter { $0.1 > 0 }.count)) min per remaining day.",
                    sentiment: .warning,
                    color: .orange
                ))
            }
        }

        // 5. Peak time — actionable scheduling advice
        let peakHour = hourlyData.max(by: { $0.totalMinutes < $1.totalMinutes })
        if let peak = peakHour, peak.totalMinutes > 30 {
            let peakSessions = hourlyData.filter { abs($0.hour - peak.hour) <= 1 }
            let peakTotal = Int(peakSessions.reduce(0.0) { $0 + $1.totalMinutes })
            let personality: String
            if peak.hour < 10 {
                personality = "Your peak window is before 10am — \(peakTotal)m focused there. Block mornings for your hardest tasks; your alertness drops ~25% after noon."
            } else if peak.hour < 14 {
                personality = "Peak focus at \(peak.label) — \(peakTotal)m total. Schedule demanding work late morning. Avoid meetings in this window."
            } else if peak.hour < 18 {
                personality = "Afternoon focuser — \(peak.label) is your peak with \(peakTotal)m. Use mornings for admin, save deep work for after lunch."
            } else {
                personality = "Night owl pattern — peak at \(peak.label) with \(peakTotal)m. Your circadian rhythm favors evening focus. Don't fight it, plan for it."
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
                    .accessibilityHidden(true)
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
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) { showAppUsage.toggle() }
                } label: {
                    HStack {
                        LiquidSectionHeader(
                            "App Usage",
                            subtitle: appUsageSummary
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showAppUsage ? 90 : 0))
                            .animation(reduceMotion ? nil : FFMotion.section, value: showAppUsage)
                            .accessibilityHidden(true)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                if showAppUsage {
                    appUsageContent
                        .padding(.top, 8)
                }
            }
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
                            .accessibilityHidden(true)
                        Text("Today's app usage will appear here as you use your Mac")
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
        analyticsReport.today.rows
            .map {
                AppUsageSummaryItem(
                    name: $0.label,
                    bundleId: $0.bundleIdentifier,
                    totalSeconds: $0.totalSeconds,
                    duringFocus: $0.duringFocusSeconds,
                    category: $0.category
                )
            }
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
                                        .foregroundStyle(LiquidDesignTokens.Surface.onProminent)
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
                    .animation(reduceMotion ? nil : FFMotion.control, value: isSelected)
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

    private var breakPerFocusSessionValue: String {
        let totalFocusSessions = focusSessions.filter(\.completed).count
        guard totalFocusSessions > 0 else { return "—" }
        let ratio = Double(totalBreaks) / Double(totalFocusSessions)
        return String(format: "%.2f", ratio)
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
                        title: "Breaks / Focus",
                        value: breakPerFocusSessionValue,
                        icon: "arrow.triangle.branch",
                        color: .teal,
                        subtitle: "Average breaks taken per completed focus session"
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
        let today = calendar.startOfDay(for: analyticsSnapshotNow)
        return (0..<30).map { offset in
            guard let day = calendar.date(byAdding: .day, value: -(29 - offset), to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return 0 }
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
            return secondHalf > 0 ? "Recent activity detected; baseline is still stabilizing." : "No measurable focus data yet."
        }
        let change = ((secondHalf - firstHalf) / firstHalf) * 100
        if change > 10 {
            return "30-day focused time is up \(Int(change))%."
        } else if change < -10 {
            return "30-day focused time is down \(Int(abs(change)))%."
        }
        return "30-day focused time is stable."
    }

    // MARK: - Science Tips

    private var scienceTipsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) { showScienceTips.toggle() }
                } label: {
                    HStack {
                        LiquidSectionHeader(
                            "Focus Science",
                            subtitle: "Research-backed tips for your patterns"
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showScienceTips ? 90 : 0))
                            .animation(reduceMotion ? nil : FFMotion.section, value: showScienceTips)
                            .accessibilityHidden(true)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                if showScienceTips {
                    VStack(spacing: 10) {
                        ForEach(contextualTips, id: \.title) { tip in
                            scienceTipCard(tip)
                        }
                    }
                    .padding(.top, 8)
                }
            }
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
        let coachCompletionSessions = coachWindowSessions

        // Tip based on average session length (with specific research)
        let avgDuration = focusSessions.isEmpty ? 0 : focusSessions.reduce(0.0) { $0 + $1.actualDuration } / Double(focusSessions.count)
        if avgDuration > 0 && avgDuration < 900 {
            tips.append(ScienceTip(
                icon: "timer",
                title: "Start Small, Build Up",
                body: "Your avg session is \(Int(avgDuration/60))m. Short sessions are fine for building the habit — completing them builds self-efficacy, which reduces procrastination over time (Steel, 2007). Try adding 5 minutes when you're ready.",
                color: .blue
            ))
        } else if avgDuration >= 900 && avgDuration < 1500 {
            tips.append(ScienceTip(
                icon: "timer",
                title: "Finding Your Rhythm",
                body: "Your avg session is \(Int(avgDuration/60))m. You're in the productive zone. Research shows 25–50 min sessions maximize deep work capacity. Experiment with slightly longer sessions when the task type calls for it.",
                color: .blue
            ))
        } else if avgDuration >= 2700 {
            tips.append(ScienceTip(
                icon: "brain",
                title: "Consider Shorter Sprints",
                body: "Sessions over 45m can deplete cognitive resources. Micro-breaks between focused sprints boost vigor by d=0.36 (Albulescu, 2022). Try splitting long sessions with 5-min breaks.",
                color: .purple
            ))
        }

        // Tip based on break behavior
        let breakTakenRatio = focusSessions.isEmpty ? 0 : Double(totalBreaks) / Double(focusSessions.count)
        if breakTakenRatio < 0.5 && focusSessions.count > 3 {
            tips.append(ScienceTip(
                icon: "cup.and.saucer.fill",
                title: "Breaks Aren't Wasted Time",
                body: "You skip breaks often. Regular rest prevents cognitive fatigue and boosts creativity. Even 5-min micro-breaks significantly restore vigor (Albulescu, 2022).",
                color: .green
            ))
        }

        // Tip based on consistency — quality-gated (must average 25+ min per active day)
        let activeDaysLast7 = last30DaysData.suffix(7).filter { $0 > 0 }.count
        let totalMinLast7 = last30DaysData.suffix(7).reduce(0, +)
        let avgMinPerActiveDay = activeDaysLast7 > 0 ? totalMinLast7 / Double(activeDaysLast7) : 0
        if activeDaysLast7 >= 5 && avgMinPerActiveDay >= 25 {
            tips.append(ScienceTip(
                icon: "flame.fill",
                title: "Strong Consistency",
                body: "You focused \(activeDaysLast7)/7 days, averaging \(Int(avgMinPerActiveDay))m per session day. Regularity at this level rewires neural pathways for sustained attention (Rozental, 2018).",
                color: .orange
            ))
        } else if activeDaysLast7 >= 5 && avgMinPerActiveDay < 25 {
            tips.append(ScienceTip(
                icon: "chart.line.uptrend.xyaxis",
                title: "Frequency Without Depth",
                body: "You show up \(activeDaysLast7)/7 days — great habit. But averaging \(Int(avgMinPerActiveDay))m per day isn't enough for deep work. Try extending one session to 25m+ — that's the threshold where flow state becomes accessible (Steel, 2007).",
                color: .blue
            ))
        } else if activeDaysLast7 <= 2 && focusSessions.count > 5 {
            tips.append(ScienceTip(
                icon: "calendar.badge.exclamationmark",
                title: "Habit Loop Breaking",
                body: "Only \(activeDaysLast7) days this week. The hardest part of any habit is restarting after a gap. Try a single 5-min session today — just starting breaks the avoidance cycle (Rozental, 2018).",
                color: .red
            ))
        }

        // Completion-based tip (using procrastination research)
        let completionRate = coachCompletionSessions.isEmpty
            ? 0
            : Double(coachCompletionSessions.filter(\.completed).count) / Double(coachCompletionSessions.count)
        if completionRate < 0.4 && coachCompletionSessions.count >= 5 {
            tips.append(ScienceTip(
                icon: "exclamationmark.triangle.fill",
                title: "Completion Challenge",
                body: "You're completing \(Int(completionRate * 100))% of sessions. This often signals the planned duration is too long. Try shorter sessions — completing them builds momentum and self-efficacy (Steel, 2007).",
                color: .red
            ))
        }

        // Mental contrasting tip based on resistance data
        let highResistanceIntents = coachWindowTaskIntents.filter { $0.expectedResistance >= 4 }
        if highResistanceIntents.count >= 3 {
            tips.append(ScienceTip(
                icon: "brain.head.profile",
                title: "High-Resistance Pattern",
                body: "You frequently face high-resistance tasks. Mental Contrasting with Implementation Intentions (MCII) — visualizing success then obstacles — improves goal attainment by g=0.336 (Wang, 2021). The pre-session check-in helps with this.",
                color: .purple
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
                .accessibilityHidden(true)

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
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
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
