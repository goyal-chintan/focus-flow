import SwiftUI
import SwiftData

/// Focusing and paused popover (screen audit): log while you work. "○ {block task} · 2/5 tasks"
/// with a tick for the block's own task, and "{key result} +1" when the project has a count
/// key result (same choice as the notch).
struct PopoverBlockLogRow: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped after a +1 so the count re-reads the store (goal entries are not observed).
    @State private var resultRevision = 0

    var body: some View {
        let now = Date()
        let todays = timerVM.todayTasks(now: now)
        let stats = DailyTaskPlanner.stats(todays, on: now)
        let blockTask = timerVM.currentBlockTaskID.flatMap { id in todays.first { $0.id == id } }
        let result = quickResult(now: now)
        if stats.planned > 0 || result != nil {
            VStack(spacing: 8) {
                if stats.planned > 0 {
                    taskRow(blockTask, stats: stats)
                }
                if let result {
                    resultButton(result)
                }
            }
        }
    }

    private func taskRow(_ task: DailyTask?, stats: DailyTaskStats) -> some View {
        HStack(spacing: 4) {
            if let task {
                DailyTaskControl(task: task, size: 15) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        timerVM.advanceDailyTask(task)
                    }
                }
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                DailyTaskCountText(task: task)
            } else {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text("Today's tasks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text("\(stats.done)/\(stats.planned) tasks")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(stats.isComplete ? FFPalette.goal : FFPalette.accent)
                .contentTransition(.numericText())
        }
        .padding(.trailing, 10)
        .frame(minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func resultButton(_ result: (id: UUID, title: String, done: Double, target: Double)) -> some View {
        Button {
            timerVM.logGoalProgress(resultID: result.id, amount: 1)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { resultRevision += 1 }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text("\(result.title) +1")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(result.done))/\(Int(result.target))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .help("Log one more toward \(result.title)")
        .accessibilityLabel("Log one more \(result.title), \(Int(result.done)) of \(Int(result.target))")
    }

    /// The running block's project's count key result: today's lever first, else the first unfinished.
    private func quickResult(now: Date) -> (id: UUID, title: String, done: Double, target: Double)? {
        _ = resultRevision
        guard timerVM.isStarterBlock == false, let projectID = timerVM.selectedProject?.id else { return nil }
        let goals = timerVM.historyReaderActiveGoals().filter { $0.projectID == projectID }
        guard !goals.isEmpty else { return nil }
        let lever = GoalDataBuilder.levers(goals, now: now).first { $0.projectID == projectID }
        let results = goals.flatMap(\.sortedKeyResults)
        guard let result = results.first(where: { $0.id == lever?.id && $0.kind == .count })
            ?? results.first(where: { $0.kind == .count && $0.done < $0.target })
        else { return nil }
        return (result.id, result.title, result.done, result.target)
    }
}
