import SwiftUI
import SwiftData

/// Today: am I on track for today's goal, and what's next? (redesign spec §4 Today)
struct TodayView: View {
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(sort: \AppUsageEntry.date) private var usageEntries: [AppUsageEntry]
    @Query private var distractionRules: [IdleDistractionItem]
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]
    @Query private var tasks: [DailyTask]

    @State private var showManualEntry = false
    @State private var editingSession: FocusSession?
    @AppStorage("companionRequestedTab") private var requestedTabRaw: String = ""
    @Environment(\.companionNowOverride) private var nowOverride

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(snapshot: CompanionSnapshot(sessions: sessions, settings: allSettings.first, projects: projects, now: nowOverride ?? context.date))
        }
        .sheet(isPresented: $showManualEntry) {
            ManualSessionView()
        }
        .sheet(item: $editingSession) { session in
            SessionEditView(session: session)
        }
    }

    private func content(snapshot: CompanionSnapshot) -> some View {
        // Own work only, once a project is marked Work: 3h of office must not read "goal met".
        let progress = snapshot.analytics.goalProgress(snapshot.goalSamples, on: snapshot.now, goal: snapshot.goal, stretch: snapshot.stretch)
        let windows = snapshot.bestWindows
        return ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("Today", subtitle: snapshot.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Log a block", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("Log a focus block you did away from the timer")
                }

                GoalHeroView(
                    scopeLabel: snapshot.dailyGoal.label,
                    progress: progress,
                    next: snapshot.analytics.nextWindow(windows, after: snapshot.now),
                    week: snapshot.analytics.weekOverWeek(snapshot.goalSamples, goal: snapshot.goal, now: snapshot.now),
                    days: weekDots(snapshot),
                    missedYesterday: missedYesterday(snapshot),
                    now: snapshot.now
                )

                // Status first; the day's line is a strip under it, not the tallest card on top.
                DailyReminderView(style: .strip, now: snapshot.now)

                DailyTasksSection(now: snapshot.now)

                priorityBreakdown(snapshot)

                timelineSection(snapshot, windows: windows)

                distractionsSection(snapshot)
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Week dots (never miss twice, own work)

    /// Monday–Sunday of this week, marked against the daily goal on own work.
    private func weekDots(_ snapshot: CompanionSnapshot) -> [GoalHeroView.WeekDot] {
        let calendar = snapshot.calendar
        let today = snapshot.today.start
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: snapshot.thisWeek.start) }
        return snapshot.goalDays(dates).map { total in
            let mark: GoalHeroView.WeekDot.Mark
            if total.day > today {
                mark = .future
            } else if total.seconds >= snapshot.goal(on: total.day) {
                mark = .met
            } else if total.seconds > 0 {
                mark = .partial
            } else {
                mark = total.day == today ? .open : .missed
            }
            let goal = snapshot.goal(on: total.day)
            let fraction = goal > 0 ? min(1, total.seconds / goal) : 0
            return GoalHeroView.WeekDot(day: total.day, seconds: total.seconds, mark: mark, fraction: fraction)
        }
    }

    /// Nothing toward the goal yesterday and nothing yet today: today decides the habit.
    private func missedYesterday(_ snapshot: CompanionSnapshot) -> Bool {
        guard let yesterday = snapshot.calendar.date(byAdding: .day, value: -1, to: snapshot.today.start),
              snapshot.goalSamples.contains(where: { $0.start < yesterday }) else { return false }
        return snapshot.analytics.dayTotal(snapshot.goalSamples, on: yesterday).seconds == 0
            && snapshot.analytics.dayTotal(snapshot.goalSamples, on: snapshot.now).seconds == 0
    }

    // MARK: - Where today went (priorities-goals design §3.3)

    private func priorityBreakdown(_ snapshot: CompanionSnapshot) -> some View {
        let allocation = GoalDataBuilder.allocation(samples: snapshot.samples, projects: projects, day: snapshot.today, calendar: snapshot.calendar)
        let ranked = projects.contains { $0.priorityRank != nil }
        return FFSection("Where today went", subtitle: "In priority order, against each project's daily target.") {
            if !ranked {
                Button("Set priorities") { requestedTabRaw = CompanionTab.projects.rawValue }
                    .buttonStyle(.link)
            }
        } content: {
            PriorityBreakdownView(allocation: allocation)
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
                title: SessionRow.title(intent: session.intentText, taskTitle: taskTitle(session), achievement: nil, fallback: session.label),
                seconds: FocusSample(session).overlap(with: day)
            )
        }
        let colors = ProjectColorScale(todaySessions.map { AnalyticsProjectKey(project: $0.project, customLabel: $0.customLabel) })

        let total = snapshot.analytics.dayTotal(snapshot.samples, on: snapshot.now)
        var parts: [String] = []
        if total.blocks > 0 {
            parts.append("\(total.blocks) block\(total.blocks == 1 ? "" : "s") · avg \(FFFormat.duration(total.seconds / Double(total.blocks)))")
        }
        if !windows.isEmpty { parts.append(total.blocks > 0 ? "shaded: your usual focus hours" : "Shaded hours are your usual focus windows") }

        return FFSection("Timeline", subtitle: parts.isEmpty ? nil : parts.joined(separator: " · ")) {
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
                            SessionRow(session: session, today: day, taskTitle: taskTitle(session)) { editingSession = session }
                        }
                    }
                    .padding(.horizontal, -FFSpace.s)
                }
            }
        }
    }

    private func taskTitle(_ session: FocusSession) -> String? {
        session.taskID.flatMap { id in tasks.first { $0.id == id }?.title }
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
            FFSection("Distractions today", subtitle: "Time outside focus blocks. Tell the coach which ones count.") {
                Button("See patterns") { requestedTabRaw = CompanionTab.insights.rawValue }
                    .buttonStyle(.link)
                    .font(FFTextStyle.callout.font)
            } content: {
                VStack(spacing: FFSpace.s) {
                    ForEach(top) { item in
                        HStack(spacing: FFSpace.m) {
                            HStack(spacing: FFSpace.m) {
                                Text(item.name).ffText(.body).frame(width: 120, alignment: .leading).lineLimit(1)
                                FFValueBar(fraction: Double(item.seconds) / peak, color: FFPalette.atRisk)
                                Text(FFFormat.duration(TimeInterval(item.seconds)))
                                    .ffNumber(.body)
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                            DerailerActionButtons(name: item.name, target: item.target, isConfirmed: item.isConfirmed)
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
    }
}

// MARK: - Goal hero

private struct GoalHeroView: View {
    /// What the goal counts ("★ Learning"), shown beside the number as on Goals and the popover.
    let scopeLabel: String
    let progress: FocusAnalytics.GoalProgress
    let next: FocusAnalytics.NextWindow?
    let week: FocusAnalytics.WeekComparison
    /// This week, Monday first, against the goal (own work once a project is marked Work).
    let days: [WeekDot]
    let missedYesterday: Bool
    let now: Date

    struct WeekDot: Identifiable {
        enum Mark { case met, partial, missed, open, future }
        let day: Date
        let seconds: TimeInterval
        let mark: Mark
        /// Share of the daily goal reached (own work); a partial day fills only this far.
        var fraction: Double = 0
        var id: Date { day }
    }

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
                    ScopeChip(label: scopeLabel)
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
            HStack(spacing: 5) {
                ForEach(days) { dayDot($0) }
            }
            .padding(.top, 2)
            .help("Never miss twice. Green: goal met. Blue: showed up. Grey: missed.")
            Text(missedYesterday
                 ? "Missed yesterday · don't miss twice"
                 : "Goal met \(week.thisWeekGoalDays) day\(week.thisWeekGoalDays == 1 ? "" : "s")")
                .ffText(.caption)
                .foregroundStyle(missedYesterday ? FFPalette.atRisk : .secondary)
                .monospacedDigit()
        }
        .frame(width: 170, alignment: .leading)
    }

    private func dayDot(_ day: WeekDot) -> some View {
        let fill: Color = switch day.mark {
        case .met: FFPalette.goal
        case .partial: FFPalette.track
        case .missed: FFPalette.track
        case .open, .future: .clear
        }
        let isToday = calendar.isDate(day.day, inSameDayAs: now)
        return VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fill)
                // A partial day fills from the bottom by its share of the goal, so only a met day is solid.
                .overlay(alignment: .bottom) {
                    if day.mark == .partial {
                        Rectangle()
                            .fill(FFPalette.accent)
                            .frame(height: max(2, 14 * day.fraction))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            day.mark == .open ? FFPalette.accent : FFPalette.hairline,
                            style: StrokeStyle(lineWidth: 1, dash: day.mark == .open ? [2, 2] : [])
                        )
                )
                .frame(width: 14, height: 14)
            Text(day.day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 10, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? .primary : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.day.formatted(.dateTime.weekday(.wide))): \(FFFormat.duration(day.seconds))")
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
