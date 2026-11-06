import SwiftUI
import SwiftData

/// Goals → Daily goal (structural redesign 2026-10-30): the one place the daily goal is set. It
/// says what the goal counts (the scope label sits beside the number, as on the popover and the
/// notch), and either follows the counted projects' daily targets or uses a fixed number.
struct DailyGoalCard: View {
    @Bindable var settings: AppSettings
    let projects: [Project]
    let now: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Folded to its one line: it's a setting, changed rarely (Goals clarity 2026-11-02).
    @State private var editing = false

    private var goal: DailyGoal {
        GoalDataBuilder.dailyGoal(projects: projects, settings: settings, on: now)
    }

    /// The counted projects with a target today, largest first ("Learning 4h").
    private var targetRows: [(name: String, minutes: Int)] {
        let keys = goal.scope.keys
        return projects
            .filter { keys?.contains(GoalDataBuilder.projectKey($0)) ?? true }
            .compactMap { project in project.dailyTarget(on: now).map { (project.name, $0) } }
            .sorted { $0.minutes > $1.minutes }
    }

    var body: some View {
        let goal = goal
        FFSection("Daily goal", subtitle: "Focus time a day, the number on your rings. \(goal.scope.countsSentence)") {
            Button(editing ? "Done" : "Change") {
                withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) { editing.toggle() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(editing ? "Done changing the daily goal" : "Change the daily goal")
        } content: {
            VStack(alignment: .leading, spacing: FFSpace.m) {
                headline(goal)
                if editing {
                    Divider()
                    followsTargetsRow(goal)
                    fixedRow(goal)
                    stretchRow(goal)
                }
            }
            .animation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion), value: goal.source)
        }
    }

    // MARK: Rows

    /// "4h a day  [★ Learning]" and where the number comes from.
    private func headline(_ goal: DailyGoal) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: FFSpace.s) {
                Text(FFFormat.duration(goal.seconds)).ffNumber(.largeTitle)
                Text("a day").ffText(.title3).foregroundStyle(.secondary)
                ScopeChip(label: goal.label)
            }
            Text(sourceLine(goal)).ffText(.caption).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func sourceLine(_ goal: DailyGoal) -> String {
        switch goal.source {
        case .projectTargets:
            let parts = targetRows.map { "\($0.name) \(FFFormat.duration(TimeInterval($0.minutes * 60)))" }
            return parts.count > 1
                ? "Sum of today's project targets: \(parts.joined(separator: " + "))"
                : "From today's project target: \(parts.first ?? "")"
        case .fixed where goal.followsTargets:
            return "No counted project has a target today, so the fixed goal applies."
        case .fixed:
            return "A fixed number, the same every day."
        case .dayType(let type):
            return "Your \(type.title.lowercased()) target, set in Settings → Focus."
        }
    }

    private func followsTargetsRow(_ goal: DailyGoal) -> some View {
        HStack(spacing: FFSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use the sum of project targets").ffText(.body)
                Text("Set a project's daily target in its Edit sheet. Weekday-only targets skip weekends.")
                    .ffText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: FFSpace.s)
            Toggle("Use the sum of project targets", isOn: Binding(
                get: { settings.dailyGoalFollowsTargets ?? true },
                set: { settings.dailyGoalFollowsTargets = $0; save() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityIdentifier("goals.dailyGoal.followsTargets")
        }
    }

    private func fixedRow(_ goal: DailyGoal) -> some View {
        stepperRow(
            title: "Fixed goal",
            caption: goal.followsTargets ? "Used on days no counted project has a target." : nil,
            value: Int(goal.fixedSeconds / 60),
            range: 30...480,
            dimmed: goal.source == .projectTargets
        ) { minutes in
            let extra = max(0, settings.dailyStretchGoal - settings.dailyFocusGoal)
            settings.dailyFocusGoal = TimeInterval(minutes * 60)
            settings.dailyStretchGoal = settings.dailyFocusGoal + extra
        }
    }

    private func stretchRow(_ goal: DailyGoal) -> some View {
        let extraMinutes = Int((goal.stretchSeconds - goal.seconds) / 60)
        return stepperRow(
            title: "Stretch on top",
            caption: "The bonus once the goal is met: \(FFFormat.duration(goal.stretchSeconds)) today.",
            value: extraMinutes,
            range: 0...240,
            prefix: "+"
        ) { minutes in
            settings.dailyStretchGoal = settings.dailyFocusGoal + TimeInterval(minutes * 60)
        }
    }

    private func stepperRow(
        title: String,
        caption: String?,
        value: Int,
        range: ClosedRange<Int>,
        prefix: String = "",
        dimmed: Bool = false,
        set: @escaping (Int) -> Void
    ) -> some View {
        let text = prefix + (value == 0 ? "0m" : FFFormat.duration(TimeInterval(value * 60)))
        return HStack(spacing: FFSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ffText(.body)
                if let caption { Text(caption).ffText(.caption).monospacedDigit() }
            }
            Spacer(minLength: FFSpace.s)
            Text(text)
                .ffNumber(.body)
                .contentTransition(.numericText())
            Stepper(title, value: Binding(get: { value }, set: { set($0); save() }), in: range, step: 15)
                .labelsHidden()
                .accessibilityValue(text)
        }
        .opacity(dimmed ? 0.55 : 1)
        .frame(minHeight: 30)
    }

    private func save() {
        try? modelContext.save()
    }
}

/// The goal's scope beside its number: "★ Learning", "Own work", "All focus".
struct ScopeChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(FFPalette.accent)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(FFPalette.accent.opacity(0.14)))
            .lineLimit(1)
            .accessibilityLabel("Counts \(label)")
    }
}
