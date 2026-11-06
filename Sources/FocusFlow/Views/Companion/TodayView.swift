import SwiftUI
import SwiftData
import Charts

/// Today (coach v8 §3.6, calm surfaces): one sentence on where the day stands ("1h 43m of 2h 30m ·
/// on pace · leave day"), the day's line, the next block, your tasks, and the day hour by hour with
/// its blocks under it. The week, the priorities and the distractions live in Insights and Goals.
struct TodayView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]
    @Query private var tasks: [DailyTask]
    @Query(sort: \PlannedBlock.startAt) private var plans: [PlannedBlock]

    @State private var showManualEntry = false
    @State private var editingSession: FocusSession?
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
        // Read so a new block or a changed day-type target redraws the sentence.
        let _ = (timerVM.todayFocusTime, timerVM.dayTargetsRevision)
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

                sentenceCard(snapshot)

                DailyTasksSection(now: snapshot.now)

                daySection(snapshot)
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The one sentence, the day's line and the next block

    private func sentenceCard(_ snapshot: CompanionSnapshot) -> some View {
        let now = snapshot.now
        let goal = timerVM.dailyGoal(now: now)
        // Done comes from the page's own samples (what the goal counts), as the old ring did.
        let sentence = CalmSurfaces.todaySentence(
            doneSeconds: snapshot.analytics.dayTotal(snapshot.goalSamples, on: now).seconds,
            goal: goal,
            pace: timerVM.goalPacing(now: now).tier,
            dayType: timerVM.settledDayType(now: now),
            format: FFFormat.duration
        )
        return VStack(alignment: .leading, spacing: FFSpace.m) {
            HStack(alignment: .firstTextBaseline, spacing: FFSpace.s) {
                Text(sentence)
                    .ffText(.title3)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.sentence")
                Spacer(minLength: FFSpace.s)
                ScopeChip(label: goal.label)
            }
            if let next = nextLine(snapshot) {
                Label(next, systemImage: "alarm")
                    .ffText(.callout)
                    .monospacedDigit()
            }
            // The day's line shows here only (coach v8 §3.6: the quote once a day, on one surface).
            DailyReminderView(style: .strip, now: now)
        }
        .padding(FFSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ffSurface(radius: FFRadius.hero)
    }

    /// "Next: planned 20:00 · 25m · Window functions", else the next good window.
    private func nextLine(_ snapshot: CompanionSnapshot) -> String? {
        let now = snapshot.now
        if let plan = plans.first(where: { $0.status == .planned && $0.startAt > now.addingTimeInterval(-CoachPlannedCue.lateStart) }) {
            let when = snapshot.calendar.isDate(plan.startAt, inSameDayAs: now)
                ? FFFormat.clock(plan.startAt)
                : "\(plan.startAt.formatted(.dateTime.weekday(.abbreviated))) \(FFFormat.clock(plan.startAt))"
            return "Next: planned \(when) · \(plan.minutes)m\(plan.title.map { " · \($0)" } ?? "")"
        }
        guard let next = snapshot.analytics.nextWindow(snapshot.bestWindows, after: now) else { return nil }
        if next.isNow { return "You're in a good window until \(FFFormat.hourLabel(next.window.startHour + next.window.hourCount))" }
        let time = FFFormat.clock(next.start)
        return snapshot.calendar.isDate(next.start, inSameDayAs: now)
            ? "Next good window \(time)"
            : "Next good window \(next.start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    // MARK: - Your day: hour by hour, then its blocks

    private func daySection(_ snapshot: CompanionSnapshot) -> some View {
        let day = snapshot.today
        let timeline = timerVM.dayTimeline(day.start, now: snapshot.now)
        let todaySessions = sessions.filter { $0.type == .focus && $0.actualDuration >= 60 && $0.effectiveEnd > day.start && $0.startedAt < day.end }
        let kinds = DayTimelineChart.Kind.allCases.filter { kind in timeline.hours.contains { kind.minutes(in: $0) >= 1 } }
        let subtitle = timeline.hasRollup
            ? "Own work, work, calls, away and pulls, hour by hour."
            : "Your blocks, hour by hour. Calls, away time and pulls show from the next hours on."
        return FFSection("Your day", subtitle: subtitle) {
            HStack(spacing: FFSpace.m) {
                ForEach(kinds) { kind in
                    FFLegendItem(color: kind.color, label: kind.title)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.m) {
                if timeline.activeRange != nil {
                    DayTimelineChart(timeline: timeline, now: snapshot.now)
                }
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
}

// MARK: - Day timeline chart

/// One bar per hour, stacked by what the hour held (`DayTimeline`): own work, work, calls, away,
/// pulls and other laptop time. Only the hours with something in them are drawn.
struct DayTimelineChart: View {
    let timeline: DayTimeline
    let now: Date

    @State private var reveal = 0.0

    enum Kind: String, CaseIterable, Identifiable {
        case own, work, call, away, pull, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .own: "Own work"
            case .work: "Work blocks"
            case .call: "Calls"
            case .away: "Away"
            case .pull: "Pulls"
            case .other: "Other"
            }
        }

        var color: Color {
            switch self {
            case .own: FFPalette.accent
            case .work: FFPalette.comparison
            case .call: Color.purple.opacity(0.7)
            case .away: FFPalette.track
            case .pull: FFPalette.atRisk
            case .other: Color.secondary.opacity(0.35)
            }
        }

        func minutes(in hour: DayTimeline.Hour) -> Double {
            switch self {
            case .own: hour.own
            case .work: hour.work
            case .call: hour.call
            case .away: hour.away
            case .pull: hour.pull
            case .other: hour.other
            }
        }
    }

    private struct Bar: Identifiable {
        let hour: Int
        let kind: Kind
        let minutes: Double
        var id: String { "\(hour)-\(kind.rawValue)" }
    }

    private var range: ClosedRange<Int> {
        guard let active = timeline.activeRange else { return 8...20 }
        return max(0, active.lowerBound - 1)...min(23, active.upperBound + 1)
    }

    private var bars: [Bar] {
        range.flatMap { index in
            Kind.allCases.compactMap { kind in
                let minutes = kind.minutes(in: timeline.hours[index])
                return minutes >= 0.5 ? Bar(hour: index, kind: kind, minutes: minutes) : nil
            }
        }
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(x: .value("Hour", Double(bar.hour) + 0.5), y: .value("Minutes", bar.minutes * reveal), width: .fixed(14))
                .foregroundStyle(by: .value("Kind", bar.kind.title))
        }
        .chartForegroundStyleScale(domain: Kind.allCases.map(\.title), range: Kind.allCases.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: Double(range.lowerBound)...Double(range.upperBound + 1))
        .chartYScale(domain: 0...60)
        .chartXAxis {
            AxisMarks(values: Array(range).filter { $0 % 2 == 0 }) { value in
                AxisValueLabel { Text(FFFormat.hourLabel(value.as(Int.self) ?? 0)).font(.system(size: 10)) }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 30, 60]) { value in
                AxisGridLine().foregroundStyle(FFPalette.gridLine)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)m").font(.system(size: 10)) }
            }
        }
        .frame(height: 140)
        .ffReveal($reveal, trigger: timeline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["\(FFFormat.duration(timeline.ownMinutes * 60)) own work"]
        if timeline.workMinutes >= 1 { parts.append("\(FFFormat.duration(timeline.workMinutes * 60)) work blocks") }
        if timeline.callMinutes >= 1 { parts.append("\(FFFormat.duration(timeline.callMinutes * 60)) in calls") }
        if timeline.pullMinutes >= 1 { parts.append("\(FFFormat.duration(timeline.pullMinutes * 60)) on pulls") }
        return "Your day: " + parts.joined(separator: ", ")
    }
}
