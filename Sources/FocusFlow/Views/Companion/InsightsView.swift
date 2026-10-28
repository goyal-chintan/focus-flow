import SwiftUI
import SwiftData
import Charts

/// Insights: when do I focus best, what derails me, is my work real, is the coach helping?
/// Every number here is computed from the local store by FocusAnalytics; nothing is hardcoded.
struct InsightsView: View {
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Environment(\.companionNowOverride) private var nowOverride
    @Query(sort: \AppUsageEntry.date) private var usageEntries: [AppUsageEntry]
    @Query(sort: \InterventionAttempt.deliveredAt) private var attempts: [InterventionAttempt]
    @Query private var priorities: [WeeklyPriority]
    @Query private var distractionRules: [IdleDistractionItem]

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, now: nowOverride ?? Date())
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("Insights", subtitle: "From your sessions and app usage over the last 8 weeks")
                weekSummary(snapshot)
                DriftReportSection(snapshot: snapshot)
                CoachLearnedSection(now: snapshot.now)
                whenYouFocus(snapshot)
                derailers(snapshot)
                realWork(snapshot)
                weeklyPriorities(snapshot)
                coach(snapshot)
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - This week

    private func weekSummary(_ snapshot: CompanionSnapshot) -> some View {
        let comparison = snapshot.analytics.weekOverWeek(snapshot.samples, goal: snapshot.goal, now: snapshot.now)
        let delta = comparison.deltaSeconds
        let deltaCaption: String = comparison.lastWeekSameSpanSeconds > 0
            ? "\(FFFormat.signedDuration(delta)) vs this point last week"
            : "Nothing at this point last week"
        return HStack(alignment: .top, spacing: FFSpace.l) {
            FFStat(label: "Focus this week", value: FFFormat.duration(comparison.thisWeekSeconds), caption: deltaCaption)
            Divider()
            FFStat(label: "Last week", value: FFFormat.duration(comparison.lastWeekSeconds), caption: "Full week")
            Divider()
            FFStat(
                label: "Days goal met",
                value: "\(comparison.thisWeekGoalDays)",
                caption: "\(comparison.lastWeekGoalDays) last week",
                valueColor: comparison.thisWeekGoalDays > 0 ? FFPalette.goal : nil
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(FFSpace.l)
        .ffSurface()
    }

    // MARK: - When you focus

    private func whenYouFocus(_ snapshot: CompanionSnapshot) -> some View {
        let matrix = snapshot.analytics.hourOfWeek(snapshot.samples, weeks: 8, now: snapshot.now)
        let windows = snapshot.analytics.bestWindows(matrix)
        let subtitle: String = windows.isEmpty
            ? "Focus minutes by weekday and hour"
            : "Your best windows: \(FocusAnalytics.windowsSummary(windows))"
        return FFSection("When you focus", subtitle: subtitle) {
            if matrix.isEmpty {
                FFEmptyState(systemImage: "clock", message: "No focus blocks in the last 8 weeks", detail: "Your usual focus hours appear here once you've logged a few blocks.")
            } else {
                HourOfWeekHeatmap(matrix: matrix, windows: windows)
                Text("Minutes focused, averaged over \(matrix.weeksObserved) week\(matrix.weeksObserved == 1 ? "" : "s"). The coach's own start model is above.")
                    .ffText(.caption)
            }
        }
    }

    // MARK: - Derailers

    private func derailers(_ snapshot: CompanionSnapshot) -> some View {
        let keys = DerailerRuleKeys.from(distractionRules)
        let items = snapshot.analytics.derailers(
            usageEntries.map(UsageSample.init),
            now: snapshot.now,
            confirmedKeys: keys.confirmed,
            allowedKeys: keys.allowed,
            limit: 6
        )
        return FFSection("What derails you", subtitle: "Time outside focus blocks. Work tools like Slack, Cursor and Claude never count.") {
            if !items.isEmpty {
                HStack(spacing: FFSpace.m) {
                    FFLegendItem(color: FFPalette.atRisk, label: "This week")
                    FFLegendItem(color: FFPalette.comparison, label: "Last week")
                }
            }
        } content: {
            if items.isEmpty {
                FFEmptyState(systemImage: "checkmark.seal", message: "No derailers tracked this week or last", detail: "Streaming and social sites you visit outside focus show up here.")
            } else {
                DerailerChart(items: items)
            }
        }
    }

    // MARK: - Real work vs busywork

    private func realWork(_ snapshot: CompanionSnapshot) -> some View {
        let interval = DateInterval(start: snapshot.calendar.date(byAdding: .day, value: -28, to: snapshot.today.start) ?? snapshot.today.start, end: snapshot.now)
        let overall = snapshot.analytics.outcomeMix(snapshot.samples, in: interval)
        let byProject = snapshot.analytics.outcomeMixByProject(snapshot.samples, in: interval)
        let subtitle = overall.ratedCount > 0
            ? "\(FFFormat.percent(overall.realWorkShare)) of rated blocks moved real work forward · last 4 weeks"
            : "Your own rating of each block · last 4 weeks"
        return FFSection("Real work vs busywork", subtitle: subtitle) {
            if overall.ratedCount == 0 {
                FFEmptyState(
                    systemImage: "checklist",
                    message: "Rate your sessions after each block to see this",
                    detail: "Pick Shipped, Moved it forward or Busywork when a block ends."
                )
            } else {
                VStack(alignment: .leading, spacing: FFSpace.l) {
                    OutcomeMixBar(mix: overall, height: 12)
                    if byProject.count > 1 || byProject.first?.project != .unassigned {
                        OutcomeByProjectChart(rows: byProject)
                    }
                    Text("\(overall.ratedCount) rated · \(overall.unratedCount) not rated")
                        .ffText(.caption)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Weekly priorities

    private func weeklyPriorities(_ snapshot: CompanionSnapshot) -> some View {
        let breakdown = snapshot.analytics.priorityBreakdown(snapshot.samples, priorities: priorities.map(PrioritySample.init), now: snapshot.now)
        return FFSection("Weekly priorities", subtitle: "Focus time tagged to each of this week's priorities") {
            if breakdown.priorities.isEmpty {
                FFEmptyState(
                    systemImage: "flag",
                    message: "No priorities set for this week",
                    detail: "Name 1–3 outcomes for the week and tag blocks to them when you start."
                )
            } else {
                let peak = max(breakdown.priorities.map(\.seconds).max() ?? 0, breakdown.untaggedSeconds, 1)
                VStack(spacing: FFSpace.m) {
                    ForEach(breakdown.priorities) { item in
                        priorityRow(
                            title: item.priority.title,
                            done: item.priority.isDone,
                            seconds: item.seconds,
                            detail: "\(item.sessions) block\(item.sessions == 1 ? "" : "s")",
                            fraction: item.seconds / peak,
                            color: FFPalette.accent
                        )
                    }
                    if breakdown.untaggedSeconds > 0 {
                        priorityRow(
                            title: "Not tagged",
                            done: false,
                            seconds: breakdown.untaggedSeconds,
                            detail: "other focus",
                            fraction: breakdown.untaggedSeconds / peak,
                            color: FFPalette.comparison
                        )
                    }
                }
            }
        }
    }

    private func priorityRow(title: String, done: Bool, seconds: TimeInterval, detail: String, fraction: Double, color: Color) -> some View {
        HStack(spacing: FFSpace.m) {
            HStack(spacing: FFSpace.xs) {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FFPalette.goal).accessibilityLabel("Done")
                }
                Text(title).ffText(.body).lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)
            FFValueBar(fraction: fraction, color: color, height: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(FFFormat.duration(seconds)).ffNumber(.body)
                Text(detail).ffText(.caption).monospacedDigit()
            }
            .frame(width: 80, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Coach

    private func coach(_ snapshot: CompanionSnapshot) -> some View {
        let interval = DateInterval(start: snapshot.calendar.date(byAdding: .day, value: -27, to: snapshot.today.start) ?? snapshot.today.start, end: snapshot.now)
        let result = snapshot.analytics.coachEffectiveness(
            prompts: attempts.map(PromptSample.init),
            sessions: snapshot.samples,
            in: interval
        )
        let rescue = snapshot.analytics.rescueEffectiveness(
            rescues: attempts.compactMap { RescueSample(contextKey: $0.contextKey, deliveredAt: $0.deliveredAt) },
            sessions: snapshot.samples,
            in: interval
        )
        let starterMinutes = CoachStarterBlock.clampedMinutes(allSettings.first?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        return FFSection("Is the coach helping?", subtitle: "A prompt counts when you start a block within 10 minutes · last 4 weeks") {
            if !result.hasData && !rescue.hasRescues && rescue.starterBlocks == 0 {
                FFEmptyState(systemImage: "bell.slash", message: "No coach prompts in the last 4 weeks")
            } else {
                VStack(alignment: .leading, spacing: FFSpace.l) {
                    HStack(alignment: .top, spacing: FFSpace.l) {
                        FFStat(
                            label: "Prompt → start",
                            value: FFFormat.percent(result.rate ?? 0),
                            caption: "\(result.startsWithinWindow) of \(result.prompts) prompts",
                            valueColor: nil
                        )
                        Divider()
                        FFStat(
                            label: "Prompts per day",
                            value: String(format: "%.1f", result.promptsPerDay),
                            caption: "Over \(result.days) day\(result.days == 1 ? "" : "s")"
                        )
                        Divider()
                        if let silent = result.silentBaseline {
                            FFStat(
                                label: "Without a prompt",
                                value: FFFormat.percent(silent.rate),
                                caption: "Coach stayed quiet \(silent.prompts) times"
                            )
                        } else {
                            FFStat(label: "Prompts shown", value: "\(result.prompts)", caption: "Last 4 weeks")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if !result.byStyle.isEmpty {
                        VStack(alignment: .leading, spacing: FFSpace.s) {
                            Text("By style").ffText(.headline)
                            PromptArmChart(arms: result.byStyle)
                        }
                    }
                    if result.bySurface.count > 1 {
                        VStack(alignment: .leading, spacing: FFSpace.s) {
                            Text("By where it appeared").ffText(.headline)
                            PromptArmChart(arms: result.bySurface)
                        }
                    }
                    rescueRows(rescue, starterMinutes: starterMinutes)
                }
            }
        }
    }
}

extension InsightsView {
    /// Rescue loop rows: rescue → start by drift level, and starter blocks that kept going.
    @ViewBuilder
    fileprivate func rescueRows(_ rescue: FocusAnalytics.RescueEffectiveness, starterMinutes: Int) -> some View {
        if rescue.hasRescues {
            VStack(alignment: .leading, spacing: FFSpace.s) {
                Text("Rescues by level").ffText(.headline)
                PromptArmChart(arms: rescue.byLevel)
                Text("When you drift in a focus window, the ask shrinks: a full block, then 10 minutes, then a \(starterMinutes)-minute starter.")
                    .ffText(.caption)
            }
        }
        if rescue.starterBlocks > 0 {
            HStack(alignment: .top, spacing: FFSpace.l) {
                FFStat(
                    label: "\(starterMinutes)-min starts that kept going",
                    value: FFFormat.percent(rescue.keptGoingRate ?? 0),
                    caption: "\(rescue.startersKeptGoing) of \(rescue.starterBlocks) starter blocks led to 20m or more"
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Charts specific to Insights

/// One labelled row of a horizontal bar chart: label, a single-row Swift Chart, value text.
/// Rows share an x domain so bars compare across rows; hovering highlights the row.
private struct BarRow<Bars: ChartContent>: View {
    let label: String
    var detail: String?
    let value: String
    var valueDetail: String?
    let domain: ClosedRange<Double>
    var labelWidth: CGFloat = 132
    var barHeight: CGFloat = 22
    @ChartContentBuilder let bars: () -> Bars

    var body: some View {
        HStack(spacing: FFSpace.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).ffText(.body).lineLimit(1).truncationMode(.tail)
                if let detail { Text(detail).ffText(.caption).monospacedDigit() }
            }
            .frame(width: labelWidth, alignment: .leading)
            Chart { bars() }
                .chartXScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: barHeight)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).ffNumber(.body)
                if let valueDetail { Text(valueDetail).ffText(.caption).monospacedDigit() }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, FFSpace.s)
        .padding(.vertical, FFSpace.xs)
        .ffHoverRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)\(valueDetail.map { ", \($0)" } ?? "")")
    }
}

private struct DerailerChart: View {
    let items: [FocusAnalytics.Derailer]
    @State private var reveal = 0.0

    private var maxHours: Double {
        max(0.25, items.map { Double(max($0.thisWeekSeconds, $0.lastWeekSeconds)) / 3600 }.max() ?? 0)
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                BarRow(
                    label: item.name,
                    value: FFFormat.duration(TimeInterval(item.thisWeekSeconds)),
                    valueDetail: "last week \(FFFormat.duration(TimeInterval(item.lastWeekSeconds)))",
                    domain: 0...maxHours,
                    barHeight: 24
                ) {
                    BarMark(x: .value("Hours", Double(item.thisWeekSeconds) / 3600 * reveal), y: .value("Week", "This week"), height: .ratio(0.78))
                        .foregroundStyle(FFPalette.atRisk)
                        .cornerRadius(3)
                    BarMark(x: .value("Hours", Double(item.lastWeekSeconds) / 3600 * reveal), y: .value("Week", "Last week"), height: .ratio(0.78))
                        .foregroundStyle(FFPalette.comparison)
                        .cornerRadius(3)
                }
            }
        }
        .padding(.horizontal, -FFSpace.s)
        .ffReveal($reveal, trigger: items)
    }
}

private struct OutcomeByProjectChart: View {
    let rows: [FocusAnalytics.ProjectOutcomeMix]
    @State private var reveal = 0.0

    var body: some View {
        VStack(spacing: 2) {
            ForEach(rows) { row in
                BarRow(
                    label: row.project.name,
                    detail: "\(row.mix.ratedCount) rated",
                    value: FFFormat.percent(row.mix.share(.busywork)),
                    valueDetail: "busywork",
                    domain: 0...1,
                    barHeight: 12
                ) {
                    ForEach(SessionOutcome.allCases, id: \.self) { outcome in
                        BarMark(
                            x: .value("Share", row.mix.share(outcome) * reveal),
                            y: .value("Row", row.project.name),
                            height: .ratio(1)
                        )
                        .foregroundStyle(FFPalette.outcome(outcome))
                    }
                }
            }
        }
        .padding(.horizontal, -FFSpace.s)
        .ffReveal($reveal, trigger: rows)
    }
}

private struct PromptArmChart: View {
    let arms: [FocusAnalytics.PromptArm]
    @State private var reveal = 0.0

    var body: some View {
        let top = max(0.2, (arms.map(\.rate).max() ?? 0) * 1.15)
        VStack(spacing: 2) {
            ForEach(arms) { arm in
                BarRow(
                    label: arm.label,
                    value: FFFormat.percent(arm.rate),
                    valueDetail: "\(arm.starts) of \(arm.prompts)",
                    domain: 0...top,
                    barHeight: 14
                ) {
                    // Track first, so 0% rows show the same empty track as the others. A RectangleMark
                    // does not stack with the value bar (BarMarks in one category stack, which pushed it past the track).
                    RectangleMark(
                        xStart: .value("Track start", 0),
                        xEnd: .value("Track end", top),
                        y: .value("Arm", arm.label),
                        height: .ratio(1)
                    )
                    .foregroundStyle(FFPalette.track)
                    .cornerRadius(3)
                    BarMark(x: .value("Start rate", min(arm.rate, top) * reveal), y: .value("Arm", arm.label), height: .ratio(1))
                        .foregroundStyle(FFPalette.accent)
                        .cornerRadius(3)
                }
            }
        }
        .padding(.horizontal, -FFSpace.s)
        .ffReveal($reveal, trigger: arms)
    }
}
