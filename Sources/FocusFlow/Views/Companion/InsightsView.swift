import SwiftUI
import SwiftData
import Charts

/// Insights is "Your week" (coach v8 §3.4). It answers, in order: how was my week against my own
/// last 4 weeks, which days went how, what should I do next, and is the coach helping. The
/// questions and pattern sentences sit in one inbox below; the older analysis (when you focus,
/// what derails you, real work, drift) follows under "More detail" with its own range. Every number
/// is computed from the local store; nothing is hardcoded.
struct InsightsView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Environment(\.companionNowOverride) private var nowOverride
    @Query(sort: \AppUsageEntry.date) private var usageEntries: [AppUsageEntry]
    @Query private var distractionRules: [IdleDistractionItem]
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]
    /// The detail sections' one range, remembered per Mac.
    @AppStorage("insightsRange", store: AppIsolation.defaults) private var range: InsightsRange = .month
    @State private var selectedDay: Date?

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, projects: projects, now: nowOverride ?? Date())
        let now = snapshot.now
        // Answers (a day type, an applied recommendation, a target) redraw the page.
        let _ = (timerVM.lifeRevision, timerVM.dayTargetsRevision)
        let week = timerVM.yourWeek(now: now)
        let recs = timerVM.lifeRecommendations(now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("Your week", subtitle: "\(week.span) · against your own last 4 weeks") {
                    Button {
                        timerVM.requestWeeklyReview()
                    } label: {
                        Label("Weekly review", systemImage: "calendar.badge.checkmark")
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("insights.weeklyReview")
                }
                FFSection {
                    VStack(alignment: .leading, spacing: FFSpace.l) {
                        WeekVerdictSection(week: week)
                        WeekTrendStrip(trends: week.trends)
                    }
                }
                rhythmSection(now: now)
                daysSection(week, now: now)
                doThisNext(recs, now: now)
                CoachHelpingSection(helping: timerVM.coachHelping(now: now))
                CoachNoticedSection(days: 28, now: now)
                FFPageHeader("More detail", subtitle: "When you focus, what derails you, real work or busywork") {
                    FFSegmentedPicker(title: "Range", options: InsightsRange.allCases, selection: $range, label: \.label)
                        .accessibilityIdentifier("insights.range")
                }
                .padding(.top, FFSpace.l)
                whenYouFocus(snapshot)
                derailers(snapshot)
                realWork(snapshot)
                DriftReportSection(snapshot: snapshot, days: range.days)
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Your week

    /// How you sit and where this week's hours went (6 Nov 2026).
    private func rhythmSection(now: Date) -> some View {
        let calendar = Calendar.current
        var totals: [LeakCategory: Double] = [:]
        var span = 0.0
        var days = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else { continue }
            let account = timerVM.dayAccount(day, now: now)
            // Only days with the hourly record: before it, a day's span is a guess from its blocks.
            guard account.hasRollup else { continue }
            days += 1
            span += account.spanMinutes
            for (k, v) in account.minutes { totals[k, default: 0] += v }
        }
        return FocusRhythmSection(rhythm: timerVM.focusRhythm(now: now), week: totals, weekSpan: span, recordedDays: days)
    }

    private func daysSection(_ week: YourWeek, now: Date) -> some View {
        FFSection("Days", subtitle: "Was the day planned, and did own work happen? Click a day for its hours.") {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                WeekDaysStrip(days: week.days, selected: $selectedDay)
                if let day = selectedDay, let entry = week.days.first(where: { $0.day == day }) {
                    DayTimelineView(entry: entry, timeline: timerVM.dayTimeline(day, now: now)) { type in
                        timerVM.setDayType(day, type: type)
                    }
                    .transition(.opacity)
                    // The day's gaps between sittings, each with "Why?" (label past days here).
                    DayAccountSection(account: timerVM.dayAccount(day, now: now), now: now,
                    setReason: { start, reason in
                        timerVM.setGapReason(reason, for: start) },
                    split: { timerVM.splitGap(at: $0) }, join: { timerVM.joinGap(at: $0) }, isSplitPoint: { timerVM.isSplitPoint($0) })
                }
            }
        }
    }

    private func doThisNext(_ recs: [LifeRecommendation], now: Date) -> some View {
        FFSection("Do this next", subtitle: "From your own days, strongest first. One action each; next week says whether it worked.") {
            VStack(alignment: .leading, spacing: FFSpace.s) {
                if recs.isEmpty {
                    FFEmptyState(systemImage: "checkmark.seal", message: "Nothing to change right now",
                                 detail: "Recommendations appear when your days show a pattern worth acting on: lost weekends, missed targets, long breaks.")
                } else {
                    ForEach(Array(recs.enumerated()), id: \.element.id) { index, rec in
                        LifeRecommendationCard(index: index + 1, rec: rec,
                                               apply: { timerVM.applyLifeRecommendation(rec) },
                                               dismiss: { timerVM.dismissLifeRecommendation(rec) })
                    }
                }
            }
            .task(id: recs.map(\.id)) { timerVM.noteLifeRecommendationsShown(recs) }
        }
        .accessibilityIdentifier("insights.doThisNext")
    }

    // MARK: - When do I focus best?

    private func whenYouFocus(_ snapshot: CompanionSnapshot) -> some View {
        let matrix = snapshot.analytics.hourOfWeek(snapshot.samples, weeks: range.weeks, now: snapshot.now)
        let windows = snapshot.analytics.bestWindows(matrix)
        let subtitle: String = windows.isEmpty
            ? "Focus minutes by weekday and hour · \(range.phrase)"
            : "Your best windows: \(FocusAnalytics.windowsSummary(windows))"
        return FFSection("When do I focus best?", subtitle: subtitle) {
            if matrix.isEmpty {
                FFEmptyState(systemImage: "clock", message: "No focus blocks \(range.phrase)", detail: "Your usual focus hours appear here once you've logged a few blocks. Try a longer range.")
            } else {
                HourOfWeekHeatmap(matrix: matrix, windows: windows)
                Text("Minutes focused, averaged over \(matrix.weeksObserved) week\(matrix.weeksObserved == 1 ? "" : "s").")
                    .ffText(.caption)
            }
        }
    }

    // MARK: - What derails me?

    private func derailers(_ snapshot: CompanionSnapshot) -> some View {
        let keys = DerailerRuleKeys.from(distractionRules)
        let items = snapshot.analytics.derailers(
            usageEntries.map(UsageSample.init),
            lastDays: range.days,
            now: snapshot.now,
            confirmedKeys: keys.confirmed,
            allowedKeys: keys.allowed,
            limit: 6
        )
        return FFSection("What derails me?", subtitle: "Time outside focus blocks. Work tools like Slack, Cursor and Claude count only if you say so. Answer each one, for everywhere or one project: it teaches the coach.") {
            if !items.isEmpty {
                HStack(spacing: FFSpace.m) {
                    FFLegendItem(color: FFPalette.atRisk, label: range.currentLabel)
                    FFLegendItem(color: FFPalette.comparison, label: range.previousLabel)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                if items.isEmpty {
                    FFEmptyState(systemImage: "checkmark.seal", message: "No derailers tracked \(range.phrase) or the \(range.days) days before", detail: "Streaming and social sites you visit outside focus show up here.")
                } else {
                    DerailerChart(items: items)
                }
                DistractionSuggestionsList()
            }
        }
    }

    // MARK: - Real work or busywork?

    private func realWork(_ snapshot: CompanionSnapshot) -> some View {
        let interval = range.interval(now: snapshot.now, calendar: snapshot.calendar)
        let overall = snapshot.analytics.outcomeMix(snapshot.samples, in: interval)
        let byProject = snapshot.analytics.outcomeMixByProject(snapshot.samples, in: interval)
        let subtitle = overall.ratedCount > 0
            ? "\(FFFormat.percent(overall.realWorkShare)) of rated blocks moved real work forward · \(range.phrase)"
            : "Your own rating of each block · \(range.phrase)"
        return FFSection("Real work or busywork?", subtitle: subtitle) {
            if overall.ratedCount == 0 {
                FFEmptyState(
                    systemImage: "checklist",
                    message: "No rated blocks \(range.phrase)",
                    detail: "When a block ends, pick Shipped, Moved it forward or Busywork."
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
}

/// The Insights page's one range (7 days, 30 days, 8 weeks).
enum InsightsRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case eightWeeks = 56

    var id: Int { rawValue }
    var days: Int { rawValue }

    var label: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .eightWeeks: "8 weeks"
        }
    }

    /// "in the last 30 days".
    var phrase: String { "in the last \(label)" }
    var currentLabel: String { "Last \(label)" }
    var previousLabel: String { "The \(label) before" }

    /// Calendar weeks the focus heatmap averages over.
    var weeks: Int {
        switch self {
        case .week: 1
        case .month: 5
        case .eightWeeks: 8
        }
    }

    /// The last `days` days, today included, up to now.
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        return DateInterval(start: start, end: max(start, now))
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

/// Derailer rows: this period against the one before, each with "Distraction / It's work".
private struct DerailerChart: View {
    let items: [FocusAnalytics.Derailer]
    @State private var reveal = 0.0

    private var maxHours: Double {
        max(0.25, items.map { Double(max($0.thisWeekSeconds, $0.lastWeekSeconds)) / 3600 }.max() ?? 0)
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                HStack(spacing: FFSpace.s) {
                    BarRow(
                        label: item.name,
                        value: FFFormat.duration(TimeInterval(item.thisWeekSeconds)),
                        valueDetail: item.lastWeekSeconds > 0 ? "was \(FFFormat.duration(TimeInterval(item.lastWeekSeconds)))" : "new",
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
                    DerailerActionButtons(name: item.name, target: item.target, isConfirmed: item.isConfirmed)
                }
                .transition(.opacity)
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

/// Start rate per prompt style, surface or rescue level (Insights coach section).
struct PromptArmChart: View {
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
