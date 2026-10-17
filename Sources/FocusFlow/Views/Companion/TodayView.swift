import SwiftUI
import SwiftData

/// Today: am I on track for today's goal, and what's next? (redesign spec §4 Today)
struct TodayView: View {
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(sort: \AppUsageEntry.date) private var usageEntries: [AppUsageEntry]
    @Query private var priorities: [WeeklyPriority]
    @Query private var distractionRules: [IdleDistractionItem]

    @State private var showManualEntry = false
    @State private var editingSession: FocusSession?
    @AppStorage("companionRequestedTab") private var requestedTabRaw: String = ""
    @Environment(\.companionNowOverride) private var nowOverride

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(snapshot: CompanionSnapshot(sessions: sessions, settings: allSettings.first, now: nowOverride ?? context.date))
        }
        .sheet(isPresented: $showManualEntry) {
            ManualSessionView()
        }
        .sheet(item: $editingSession) { session in
            SessionEditView(session: session)
        }
    }

    private func content(snapshot: CompanionSnapshot) -> some View {
        let progress = snapshot.analytics.goalProgress(snapshot.samples, on: snapshot.now, goal: snapshot.goal, stretch: snapshot.stretch)
        let windows = snapshot.bestWindows
        return ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("Today", subtitle: snapshot.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Log session", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("Log a focus block you did away from the timer")
                }

                GoalHeroView(
                    progress: progress,
                    next: snapshot.analytics.nextWindow(windows, after: snapshot.now),
                    week: snapshot.analytics.weekOverWeek(snapshot.samples, goal: snapshot.goal, now: snapshot.now),
                    now: snapshot.now
                )

                statsRow(snapshot)

                timelineSection(snapshot, windows: windows)

                distractionsSection(snapshot)
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Stats

    private func statsRow(_ snapshot: CompanionSnapshot) -> some View {
        let today = snapshot.analytics.dayTotal(snapshot.samples, on: snapshot.now)
        let streak = snapshot.analytics.streak(snapshot.samples, goal: snapshot.goal, now: snapshot.now)
        let personal = personalWork(snapshot)
        return HStack(alignment: .top, spacing: FFSpace.l) {
            FFStat(
                label: "Focus blocks",
                value: "\(today.blocks)",
                caption: today.blocks == 0 ? "None yet today" : "Average \(FFFormat.duration(today.seconds / Double(max(1, today.blocks))))"
            )
            Divider()
            FFStat(label: "Personal work", value: personal.value, caption: personal.caption)
            Divider()
            FFStat(
                label: "Streak",
                value: streak.current == 1 ? "1 day" : "\(streak.current) days",
                caption: streakCaption(streak),
                valueColor: streak.current > 0 ? FFPalette.goal : nil
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(FFSpace.l)
        .ffSurface()
    }

    /// Time today on blocks tagged to one of this week's priorities (Coach v2 §9).
    private func personalWork(_ snapshot: CompanionSnapshot) -> (value: String, caption: String) {
        let weekIDs = Set(priorities.map(PrioritySample.init).filter { snapshot.thisWeek.contains($0.weekStart) }.map(\.id))
        guard !weekIDs.isEmpty else { return ("—", "Set weekly priorities to track this") }
        let seconds = snapshot.samples
            .filter { $0.priorityID.map(weekIDs.contains) ?? false }
            .reduce(0) { $0 + $1.overlap(with: snapshot.today) }
        return (FFFormat.duration(seconds), "On this week's priorities")
    }

    private func streakCaption(_ streak: FocusAnalytics.StreakSummary) -> String {
        switch streak.neverMissTwice {
        case .noHistory: return "Days you meet your goal"
        case .missedYesterday: return "Missed yesterday · don't miss twice"
        case .missedTwice: return "Two misses · today restarts it"
        case .onTrack: return streak.best > streak.current ? "Best \(streak.best) days" : "Your best run"
        }
    }

    // MARK: - Timeline

    private func timelineSection(_ snapshot: CompanionSnapshot, windows allWindows: [FocusAnalytics.FocusWindow]) -> some View {
        let day = snapshot.today
        // Only the windows that apply to today's day type (weekday or weekend) are shaded.
        let weekdayIndex = snapshot.analytics.mondayFirstWeekdayIndex(of: day.start)
        let windows = allWindows.filter { $0.dayScope.includes(weekdayIndex: weekdayIndex) }
        let todaySessions = sessions.filter { $0.type == .focus && $0.actualDuration >= 60 && $0.effectiveEnd > day.start && $0.startedAt < day.end }
        let blocks = todaySessions.map { session in
            TodayTimelineChart.Block(
                id: session.id,
                start: max(session.startedAt, day.start),
                end: min(session.effectiveEnd, day.end),
                project: AnalyticsProjectKey(project: session.project, customLabel: session.customLabel).name,
                title: session.intentText?.isEmpty == false ? session.intentText! : session.label,
                seconds: FocusSample(session).overlap(with: day)
            )
        }
        let colors = ProjectColorScale(todaySessions.map { AnalyticsProjectKey(project: $0.project, customLabel: $0.customLabel) })

        return FFSection("Timeline", subtitle: windows.isEmpty ? nil : "Shaded hours are your usual focus windows") {
            HStack(spacing: FFSpace.m) {
                ForEach(Array(zip(colors.domain, colors.range)), id: \.0) { name, color in
                    FFLegendItem(color: color, label: name)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.m) {
                TodayTimelineChart(day: day, blocks: blocks, windows: windows, colors: colors, now: snapshot.now)
                if todaySessions.isEmpty {
                    Text("No focus blocks yet today.").ffText(.callout)
                } else {
                    VStack(spacing: 2) {
                        ForEach(todaySessions.reversed()) { session in
                            SessionRow(session: session, today: day) { editingSession = session }
                        }
                    }
                    .padding(.horizontal, -FFSpace.s)
                }
            }
        }
    }

    // MARK: - Distractions

    @ViewBuilder
    private func distractionsSection(_ snapshot: CompanionSnapshot) -> some View {
        let keys = DerailerRuleKeys.from(distractionRules)
        let totals = snapshot.analytics.derailerTotals(
            usageEntries.map(UsageSample.init),
            in: snapshot.today,
            confirmedKeys: keys.confirmed,
            allowedKeys: keys.allowed,
            minimumSeconds: 600
        )
        if !totals.isEmpty {
            let top = Array(totals.prefix(3))
            let peak = Double(top.first?.seconds ?? 1)
            FFSection("Distractions today", subtitle: "Time outside focus blocks") {
                Button("See patterns") { requestedTabRaw = CompanionTab.insights.rawValue }
                    .buttonStyle(.link)
                    .font(FFTextStyle.callout.font)
            } content: {
                VStack(spacing: FFSpace.s) {
                    ForEach(top) { item in
                        HStack(spacing: FFSpace.m) {
                            Text(item.name).ffText(.body).frame(width: 120, alignment: .leading).lineLimit(1)
                            FFValueBar(fraction: Double(item.seconds) / peak, color: FFPalette.atRisk)
                            Text(FFFormat.duration(TimeInterval(item.seconds)))
                                .ffNumber(.body)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Goal hero

private struct GoalHeroView: View {
    let progress: FocusAnalytics.GoalProgress
    let next: FocusAnalytics.NextWindow?
    let week: FocusAnalytics.WeekComparison
    let now: Date

    @State private var reveal = 0.0
    @Environment(\.calendar) private var calendar

    private var tint: Color { progress.isMet ? FFPalette.goal : FFPalette.accent }

    var body: some View {
        HStack(spacing: FFSpace.xl) {
            ring
            VStack(alignment: .leading, spacing: FFSpace.s) {
                Text("Daily goal").ffText(.callout)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(FFFormat.duration(progress.doneSeconds)).ffNumber(.largeTitle)
                    Text("of \(FFFormat.duration(progress.goalSeconds))").ffText(.title3).foregroundStyle(.secondary)
                }
                statusLine
                if progress.isMet {
                    Text(progress.isStretchMet
                         ? "Stretch goal \(FFFormat.duration(progress.stretchSeconds)) reached"
                         : "Stretch goal \(FFFormat.duration(progress.stretchSeconds)) · \(FFFormat.duration(progress.stretchSeconds - progress.doneSeconds)) more")
                        .ffText(.caption)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: FFSpace.l)
            Divider().frame(height: 72)
            weekColumn
        }
        .padding(FFSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ffSurface(radius: FFRadius.hero)
        .ffReveal($reveal, trigger: progress.doneSeconds)
        .accessibilityElement(children: .combine)
    }

    private var weekColumn: some View {
        VStack(alignment: .leading, spacing: FFSpace.xs) {
            Text("This week").ffText(.callout)
            Text(FFFormat.duration(week.thisWeekSeconds)).ffNumber(.title3)
            Text(week.lastWeekSameSpanSeconds > 0
                 ? "\(FFFormat.signedDuration(week.deltaSeconds)) vs last week so far"
                 : "No focus this point last week")
                .ffText(.caption)
                .monospacedDigit()
            Text("Goal met \(week.thisWeekGoalDays) day\(week.thisWeekGoalDays == 1 ? "" : "s")")
                .ffText(.caption)
                .monospacedDigit()
        }
        .frame(width: 170, alignment: .leading)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(FFPalette.track, lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress.fraction * reveal)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress.isMet {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FFPalette.goal)
                    .accessibilityHidden(true)
            } else {
                Text(FFFormat.percent(progress.fraction)).ffNumber(.headline)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusLine: some View {
        if progress.isMet {
            Label("Goal met · +\(FFFormat.duration(progress.surplusSeconds))", systemImage: "checkmark.circle.fill")
                .ffText(.body)
                .foregroundStyle(FFPalette.goal)
                .monospacedDigit()
        } else {
            Text(pendingText).ffText(.body).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var pendingText: String {
        let toGo = "\(FFFormat.duration(progress.remainingSeconds)) to go"
        guard let next else { return toGo }
        if next.isNow {
            return "\(toGo) · you're in a good window until \(FFFormat.hourLabel(next.window.startHour + next.window.hourCount))"
        }
        let time = FFFormat.clock(next.start)
        if calendar.isDate(next.start, inSameDayAs: now) {
            return "\(toGo) · next good window \(time)"
        }
        return "\(toGo) · next good window \(next.start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}
