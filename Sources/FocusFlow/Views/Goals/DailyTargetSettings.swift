import SwiftUI
import SwiftData

/// Settings → Focus → "Own-work target by day type" (coach v8 §3.5–3.6). The daily goal moved here
/// from the Goals tab, with the same rules: a workday follows the counted projects' targets or a
/// fixed number, with a stretch on top. Leave, weekend, holiday and sick days each follow that goal
/// (a sick day: rest) until you give them their own number (`TimerViewModel.setDayTarget`).
struct DayTargetsSettingsSection: View {
    @Bindable var settings: AppSettings
    let save: () -> Void

    @Environment(TimerViewModel.self) private var timerVM
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]

    /// A weekday's goal: the workday target, whatever today is.
    private var workdayGoal: DailyGoal {
        GoalDataBuilder.dailyGoal(projects: projects, settings: settings, on: Self.nextWeekday(from: Date()))
    }

    var body: some View {
        // Read so a target change redraws the rows.
        let _ = timerVM.dayTargetsRevision
        let goal = workdayGoal
        let goalMinutes = Int(goal.seconds / 60)
        Section {
            // The number once: from the targets here, or the fixed goal's own row below.
            LabeledContent("Workday") {
                HStack(spacing: 6) {
                    Text(goal.source == .projectTargets ? FFFormat.duration(goal.seconds) : "the fixed goal")
                        .monospacedDigit()
                    ScopeChip(label: goal.label)
                }
            }
            .accessibilityIdentifier("settings.focus.workdayTarget")
            Toggle(isOn: Binding(
                get: { settings.dailyGoalFollowsTargets ?? true },
                set: { settings.dailyGoalFollowsTargets = $0; save() }
            )) {
                Text("Use the sum of project targets")
                Text(sourceLine(goal))
            }
            .accessibilityIdentifier("settings.focus.followsTargets")
            SettingsStepperRow(
                title: "Fixed goal",
                valueText: FFFormat.duration(goal.fixedSeconds),
                value: Binding(
                    get: { Int(settings.dailyFocusGoal / 60) },
                    set: { minutes in
                        let extra = max(0, settings.dailyStretchGoal - settings.dailyFocusGoal)
                        settings.dailyFocusGoal = TimeInterval(minutes * 60)
                        settings.dailyStretchGoal = settings.dailyFocusGoal + extra
                        save()
                    }
                ),
                range: 30...480,
                step: 15
            )
            .opacity(goal.source == .projectTargets ? 0.55 : 1)
            SettingsStepperRow(
                title: "Stretch on top",
                valueText: "+" + FFFormat.duration(max(0, settings.dailyStretchGoal - settings.dailyFocusGoal)),
                value: Binding(
                    get: { Int(max(0, settings.dailyStretchGoal - settings.dailyFocusGoal) / 60) },
                    set: { settings.dailyStretchGoal = settings.dailyFocusGoal + TimeInterval($0 * 60); save() }
                ),
                range: 0...240,
                step: 15
            )

            ForEach(CalmSurfaces.targetRows(yours: timerVM.dayTargets(), goalMinutes: goalMinutes)) { row in
                dayTypeRow(row)
            }
        } header: {
            Text("Own-work target by day type")
        } footer: {
            Text("\(goal.scope.countsSentence) A leave, weekend or holiday follows your goal until you give it its own number; a sick day is rest. The coach asks \"On leave?\" before a quiet weekday changes the target.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dayTypeRow(_ row: CalmSurfaces.TargetRow) -> some View {
        Toggle(isOn: Binding(
            get: { !row.followsGoal },
            set: { timerVM.setDayTarget(CalmSurfaces.toggledTarget(row, ownNumber: $0), for: row.type) }
        )) {
            Text(row.type.title)
            Text(row.followsGoal ? row.caption : "Its own number")
        }
        .accessibilityIdentifier("settings.focus.dayTarget.\(row.type.rawValue)")
        if let yours = row.yours {
            SettingsStepperRow(
                title: "\(row.type.title) target",
                valueText: yours == 0 ? "Rest" : FFFormat.duration(TimeInterval(yours * 60)),
                value: Binding(
                    get: { yours },
                    set: { timerVM.setDayTarget($0, for: row.type) }
                ),
                range: 0...480,
                step: 15
            )
        }
    }

    private func sourceLine(_ goal: DailyGoal) -> String {
        switch goal.source {
        case .projectTargets: "On: a weekday's goal is the sum of the counted projects' targets."
        case .fixed where goal.followsTargets: "No counted project has a target on weekdays, so the fixed goal applies."
        case .fixed: "Off: the fixed goal below, the same every day."
        case .dayType(let type): "Your \(type.title.lowercased()) target."
        }
    }

    /// Today if it is a weekday, else the next Monday (the workday goal can skip weekends).
    static func nextWeekday(from date: Date, calendar: Calendar = .current) -> Date {
        var day = date
        while DayType.isWeekend(day, calendar: calendar) {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return day
    }
}
