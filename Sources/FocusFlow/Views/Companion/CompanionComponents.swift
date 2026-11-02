import SwiftUI
import SwiftData
import Charts

// Shared pieces for the companion screens: the data snapshot, session rows, outcome bars and
// the project colour scale. Charts live in CompanionCharts.swift.

/// Everything a companion screen derives from the store for one render.
struct CompanionSnapshot {
    let analytics: FocusAnalytics
    let now: Date
    /// Focus blocks of at least one minute (breaks excluded).
    let samples: [FocusSample]
    /// What counts toward the daily goal (`GoalDataBuilder.goalScope`): the ★ #1 project, else own
    /// work once a project is marked Work, else every block. Every streak, chain, "goal met" mark and
    /// goal ring uses these, never `samples`.
    let goalSamples: [FocusSample]
    let goalScope: GoalScope
    /// True when `goalSamples` is a subset (a #1 project or own work), not every block.
    var ownWorkOnly: Bool { goalScope.isFiltered }
    /// Keys (`GoalDataBuilder.projectKey`) of Work projects, drawn faded in charts.
    let workKeys: Set<String>
    /// Today's daily goal (`GoalDataBuilder.dailyGoal`); `goal` and `stretch` are its sizes.
    let dailyGoal: DailyGoal
    let goal: TimeInterval
    let stretch: TimeInterval
    /// The goal's size per weekday (1 = Sunday): a weekday-only target makes weekends differ.
    private let goalByWeekday: [Int: TimeInterval]

    @MainActor
    init(sessions: [FocusSession], settings: AppSettings?, projects: [Project] = [], now: Date = Date(), calendar: Calendar = .current) {
        self.analytics = FocusAnalytics(calendar: calendar)
        self.now = now
        let samples = sessions
            .filter { $0.type == .focus }
            .map(FocusSample.init)
            .filter { $0.activeSeconds >= 60 }
        self.samples = samples
        let scope = GoalDataBuilder.goalScope(projects)
        self.goalScope = scope
        self.goalSamples = GoalDataBuilder.scopedSamples(samples, scope: scope)
        self.workKeys = Set(projects.filter { $0.areaRaw != nil && $0.area == .work }.map(GoalDataBuilder.projectKey))
        let dailyGoal = GoalDataBuilder.dailyGoal(projects: projects, settings: settings, on: now, calendar: calendar)
        self.dailyGoal = dailyGoal
        self.goal = max(60, dailyGoal.seconds)
        self.stretch = max(self.goal, dailyGoal.stretchSeconds)
        var byWeekday: [Int: TimeInterval] = [:]
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            byWeekday[calendar.component(.weekday, from: day)] = max(60, GoalDataBuilder.dailyGoal(projects: projects, settings: settings, on: day, calendar: calendar).seconds)
        }
        self.goalByWeekday = byWeekday
    }

    /// The daily goal's size on `day` (project targets can skip weekends).
    func goal(on day: Date) -> TimeInterval {
        goalByWeekday[calendar.component(.weekday, from: day)] ?? goal
    }

    var calendar: Calendar { analytics.calendar }
    var today: DateInterval { analytics.dayInterval(containing: now) }
    var thisWeek: DateInterval { analytics.weekInterval(containing: now) }

    /// Daily goal totals for `days` (own work once configured).
    func goalDays(_ days: [Date]) -> [FocusAnalytics.DayTotal] {
        analytics.dailyTotals(goalSamples, days: days)
    }

    var bestWindows: [FocusAnalytics.FocusWindow] {
        analytics.bestWindows(analytics.hourOfWeek(samples, weeks: 8, now: now))
    }
}

/// Stable project → colour mapping for chart scales. Project colours appear only on project marks.
struct ProjectColorScale {
    let domain: [String]
    let range: [Color]

    /// `faded`: project keys drawn at 0.45 opacity (Work projects, so own work stands out).
    init(_ keys: [AnalyticsProjectKey], faded: Set<String> = []) {
        var seen = Set<String>()
        var names: [String] = []
        var colors: [Color] = []
        for key in keys.sorted() where seen.insert(key.name).inserted {
            names.append(key.name)
            let color = FFPalette.project(key.colorName)
            colors.append(faded.contains(key.id) ? color.opacity(0.45) : color)
        }
        domain = names
        range = colors
    }

    func color(for name: String) -> Color {
        domain.firstIndex(of: name).map { range[$0] } ?? .gray
    }
}

// MARK: - Session rows

/// One focus block in a list. Click opens SessionEditView.
struct SessionRow: View {
    let session: FocusSession
    /// When set, the row shows only the part of the block inside this day. A block that started
    /// on an earlier day gets a "started yesterday" note with its full length.
    var today: DateInterval? = nil
    /// The task the block was started for (`FocusSession.taskID`), shown when it had no intent.
    var taskTitle: String? = nil
    /// On a project's page: never title a row with the project's own name, and drop it from the subtitle.
    var hidesProject = false
    var onSelect: () -> Void

    /// Seconds shown as the main duration: the overlap with `today`, or the full block.
    private var shownSeconds: TimeInterval {
        guard let today else { return session.actualDuration }
        return FocusSample(session).overlap(with: today)
    }

    private var startedBeforeDay: Bool {
        guard let today else { return false }
        return session.startedAt < today.start
    }

    private var timeRange: String {
        "\(FFFormat.clock(session.startedAt))–\(FFFormat.clock(session.effectiveEnd))"
    }

    /// What the block was for: its intent, else its task, else what it achieved; the project name
    /// only where the row isn't already on that project's page.
    private var title: String {
        Self.title(intent: session.intentText, taskTitle: taskTitle, achievement: session.achievement,
                   fallback: hidesProject ? "Focus block" : session.label)
    }

    static func title(intent: String?, taskTitle: String?, achievement: String?, fallback: String) -> String {
        for candidate in [intent, taskTitle, achievement] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return fallback
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: FFSpace.m) {
                Circle()
                    .fill(FFPalette.project(session.project?.color))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ffText(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .ffText(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: FFSpace.s)
                if let outcome = session.outcome {
                    OutcomeBadge(outcome: outcome)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(FFFormat.duration(shownSeconds))
                        .ffNumber(.body)
                    if startedBeforeDay {
                        Text("started yesterday · \(FFFormat.duration(session.actualDuration)) total")
                            .ffText(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, FFSpace.s)
            .padding(.vertical, FFSpace.s - 1)
            .frame(minHeight: 36)
            .ffHoverRow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(timeRange), \(FFFormat.duration(shownSeconds))\(startedBeforeDay ? ", started yesterday" : "")")
        .accessibilityHint("Edit session")
    }

    private var subtitle: String {
        let project = session.project?.name ?? session.customLabel
        if !hidesProject, let project, project != title { return "\(timeRange) · \(project)" }
        return timeRange
    }
}

struct OutcomeBadge: View {
    let outcome: SessionOutcome

    var body: some View {
        HStack(spacing: FFSpace.xs) {
            Circle().fill(FFPalette.outcome(outcome)).frame(width: 6, height: 6)
            Text(outcome.displayName).ffText(.caption)
        }
        .padding(.horizontal, FFSpace.s - 2)
        .padding(.vertical, 2)
        .background(Capsule().fill(FFPalette.outcome(outcome).opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Outcome mix

/// A 100% stacked bar of Shipped / Moved it forward / Busywork, with a legend.
struct OutcomeMixBar: View {
    let mix: FocusAnalytics.OutcomeMix
    var showLegend: Bool = true
    var height: CGFloat = 10
    @State private var reveal = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(SessionOutcome.allCases, id: \.self) { outcome in
                        let share = mix.share(outcome)
                        if share > 0 {
                            Rectangle()
                                .fill(FFPalette.outcome(outcome))
                                .frame(width: max(2, (geo.size.width - 4) * share * reveal))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule())
                .background(Capsule().fill(FFPalette.track))
            }
            .frame(height: height)
            .ffReveal($reveal, trigger: mix)
            .accessibilityElement()
            .accessibilityLabel(accessibilitySummary)

            if showLegend {
                HStack(spacing: FFSpace.m) {
                    ForEach(SessionOutcome.allCases, id: \.self) { outcome in
                        FFLegendItem(
                            color: FFPalette.outcome(outcome),
                            label: "\(outcome.displayName) \(FFFormat.percent(mix.share(outcome)))"
                        )
                    }
                    Spacer(minLength: 0)
                }
                .monospacedDigit()
            }
        }
    }

    private var accessibilitySummary: String {
        SessionOutcome.allCases
            .map { "\($0.displayName) \(FFFormat.percent(mix.share($0)))" }
            .joined(separator: ", ")
    }
}

// MARK: - Simple horizontal value bar

/// A thin horizontal bar used in compact lists (distractions today, priorities).
struct FFValueBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6
    @State private var reveal = 0.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FFPalette.track)
                if fraction > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geo.size.width * min(1, fraction) * reveal))
                }
            }
        }
        .frame(height: height)
        .ffReveal($reveal, trigger: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Clock override

private struct CompanionNowOverrideKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// Pins "now" for the companion screens (evidence renders and previews). `nil` = live clock.
    var companionNowOverride: Date? {
        get { self[CompanionNowOverrideKey.self] }
        set { self[CompanionNowOverrideKey.self] = newValue }
    }
}
