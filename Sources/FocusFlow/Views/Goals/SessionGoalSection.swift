import SwiftUI
import SwiftData

/// Block-end goal section (screen audit 2026-10-28): the block's project's active key results,
/// with what this block added ("+2 this block") and ± for progress no task covers.
///
/// It sits after the tasks section, so ticking a linked task visibly moves the bar here. The
/// chip counts every entry logged against this session (task ticks and steppers), so nothing is
/// counted twice: a tick adds one entry, the stepper adds another.
struct SessionGoalSection: View {
    let projectID: UUID?
    let sessionID: UUID
    /// Key results today's tasks are linked to: those are logged by ticking the task, so their row
    /// has no ± here (one way to log per screen; ticking and + double-counted the same work).
    var taskLinkedResultIDs: Set<UUID> = []

    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]

    private var relevant: [ProjectGoal] {
        guard let projectID else { return [] }
        return goals.filter { $0.status == .active && $0.projectID == projectID && !$0.keyResults.isEmpty }
    }

    var body: some View {
        let shown = relevant
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TrackedLabel(text: "Goal", font: .system(size: 11, weight: .semibold), tracking: 1.8)
                ForEach(shown) { goal in
                    SessionGoalCard(goal: goal, sessionID: sessionID, taskLinkedResultIDs: taskLinkedResultIDs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SessionGoalCard: View {
    let goal: ProjectGoal
    let sessionID: UUID
    let taskLinkedResultIDs: Set<UUID>

    var body: some View {
        let summary = GoalDataBuilder.summary(goal, now: Date())
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(goal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(summary.deadlineLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .monospacedDigit()
            }
            ForEach(Array(zip(goal.sortedKeyResults, summary.keyResults)), id: \.0.id) { pair in
                SessionKeyResultRow(keyResult: pair.0, pace: pair.1, sessionID: sessionID,
                                    loggedByTask: taskLinkedResultIDs.contains(pair.0.id))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

private struct SessionKeyResultRow: View {
    let keyResult: GoalKeyResult
    let pace: KeyResultPace
    let sessionID: UUID
    var loggedByTask = false

    @Environment(\.modelContext) private var modelContext
    @State private var bump = 0

    /// Everything this block logged on this key result (task ticks and steppers).
    private var addedThisBlock: Double {
        keyResult.entries.filter { $0.sessionID == sessionID }.reduce(0) { $0 + $1.amount }
    }

    /// The newest stepper entry from this block (not one logged through a task; any may carry a label).
    private var lastStepperEntry: GoalProgressEntry? {
        keyResult.entries
            .filter { $0.sessionID == sessionID && $0.taskID == nil && $0.amount > 0 }
            .max { $0.at < $1.at }
    }

    var body: some View { countRow }

    private var countRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(keyResult.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    if addedThisBlock > 0 { thisBlockChip }
                    Spacer(minLength: 4)
                    // Today's count beside the total (6 Nov 2026: "how many today?" had no answer here).
                    if let today = KeyResultRow.doneToday(keyResult), today > 0 {
                        Text("\(KeyResultRow.number(today)) today ·")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                            .monospacedDigit()
                    }
                    Text("\(KeyResultRow.number(pace.done)) / \(KeyResultRow.number(pace.target))\(keyResult.unit.map { " \($0)" } ?? "")")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                PaceBar(fraction: pace.fraction, expected: pace.expectedFraction, color: pace.status.color, height: 6)
            }
            if loggedByTask {
                Text("Tick its task")
                    .font(.system(size: 11))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .help("A task today counts toward this. Ticking the task logs it here.")
            } else {
                HStack(spacing: 2) {
                    stepButton("minus", label: "Remove one logged this block") {
                        if let entry = lastStepperEntry { remove(entry) }
                    }
                    .disabled(lastStepperEntry == nil)
                    stepButton("plus", label: "Add one") { add(1) }
                }
            }
        }
        .sensoryFeedback(.increase, trigger: bump)
    }

    private var thisBlockChip: some View {
        Text("+\(KeyResultRow.number(addedThisBlock)) this block")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(FFPalette.goal)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(FFPalette.goal.opacity(0.14)))
            .contentTransition(.numericText())
            .accessibilityLabel("\(KeyResultRow.number(addedThisBlock)) added this block")
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(symbol == "plus" ? FFPalette.accent.opacity(0.16) : FFPalette.track))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(symbol == "plus" ? FFPalette.accent : .secondary)
        .help(label)
        .accessibilityLabel("\(label): \(keyResult.title)")
    }

    /// Saved at once: a stepper entry is linked to this block and has no note.
    private func add(_ amount: Double) {
        let entry = GoalProgressEntry(amount: amount, sessionID: sessionID)
        modelContext.insert(entry)
        keyResult.entries.append(entry)
        try? modelContext.save()
        bump += 1
    }

    /// "−" only undoes this block's own stepper entries; task ticks are undone by unticking.
    private func remove(_ entry: GoalProgressEntry) {
        keyResult.entries.removeAll { $0.id == entry.id }
        modelContext.delete(entry)
        try? modelContext.save()
    }
}
