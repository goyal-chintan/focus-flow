import SwiftUI
import SwiftData

/// End-of-block logging against the plan (daily tasks design §2, screen audit 2026-10-28).
///
/// - Today's other tasks (this project first, up to five) with a tick. A tick is credited to
///   this block and feeds a linked goal; it saves at once.
/// - "Add something you finished": a task created already done, credited to this block.
/// - "Next step (for later)": an open task for today on this project. It replaces the old
///   free-text carry-forward note, which nothing read.
///
/// The block's own task is asked about separately ("Did you finish it?"), so it is left out here.
struct SessionTasksSection: View {
    let sessionID: UUID
    /// The task the block was started for. Shown in "Did you finish it?", not in this list.
    let blockTaskID: UUID?
    let projectID: UUID?

    @Environment(TimerViewModel.self) private var timerVM
    @Query private var tasks: [DailyTask]
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]
    @State private var doneTitle = ""
    @State private var nextTitle = ""
    @State private var lastNextStep: String?

    static let maxRows = 5

    init(sessionID: UUID, blockTaskID: UUID?, projectID: UUID?, now: Date = Date()) {
        self.sessionID = sessionID
        self.blockTaskID = blockTaskID
        self.projectID = projectID
        let since = Calendar.current.startOfDay(for: now)
        _tasks = Query(filter: #Predicate<DailyTask> { $0.day >= since })
    }

    /// Open tasks plus anything ticked in this block, this project first; never the block's task.
    private var shown: [DailyTask] {
        let todays = DailyTaskPlanner.tasks(tasks, on: Date())
        let relevant = todays.filter { $0.id != blockTaskID && (!$0.isDone || $0.sessionID == sessionID) }
        let sorted = relevant.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element), right = rank(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        return Array(sorted.map(\.element).prefix(Self.maxRows))
    }

    private func rank(_ task: DailyTask) -> Int {
        if projectID != nil, task.projectID == projectID { return 0 }
        return 1
    }

    private var resultTitles: [UUID: String] {
        Dictionary(goals.flatMap(\.keyResults).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let stats = DailyTaskPlanner.stats(tasks, on: Date())
        VStack(alignment: .leading, spacing: 8) {
            header(stats)
            let rows = shown
            DailyTaskReceiptBanner(compact: true)
            if !rows.isEmpty {
                VStack(spacing: 2) {
                    ForEach(rows) { task in
                        row(task)
                    }
                }
            }
            entryField(
                symbol: "plus",
                placeholder: "Add something you finished",
                text: $doneTitle,
                accessibility: "Add a task you finished in this block",
                submit: addDone
            )
            entryField(
                symbol: "arrow.right",
                placeholder: "Next step (for later)",
                text: $nextTitle,
                accessibility: "Add the next step as an open task for today",
                submit: addNextStep
            )
            if let lastNextStep {
                Text("Added to today: \(lastNextStep)")
                    .font(.system(size: 11))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
    }

    private func header(_ stats: DailyTaskStats) -> some View {
        HStack(spacing: 8) {
            TrackedLabel(text: "Tasks", font: .system(size: 11, weight: .semibold), tracking: 1.8)
            if stats.planned > 0 {
                Text("\(stats.label) today")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(stats.isComplete ? FFPalette.goal : LiquidDesignTokens.Surface.onSurfaceMuted)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
        }
    }

    private func row(_ task: DailyTask) -> some View {
        HStack(spacing: 6) {
            DailyTaskControl(task: task, resultTitle: task.keyResultID.flatMap { resultTitles[$0] }, size: 17) {
                withAnimation(.smooth(duration: 0.25)) {
                    timerVM.advanceDailyTask(task, sessionID: sessionID)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 13))
                        .strikethrough(task.isDone, color: .secondary)
                        .lineLimit(1)
                    DailyTaskCountText(task: task)
                }
                if let caption = Self.goalCaption(task, resultTitles: resultTitles) {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(task.isDone ? 0.06 : 0.03)))
    }

    static func goalCaption(_ task: DailyTask, resultTitles: [UUID: String]) -> String? {
        guard let resultID = task.keyResultID, let title = resultTitles[resultID] else { return nil }
        return goalCaption(task, resultTitle: title)
    }

    /// Says what the control does, then what it did: "Each + logs 1 to SQL" (counted, open),
    /// "Counts 1 toward SQL" (one-off, open), "Logged 3 to SQL" (done).
    static func goalCaption(_ task: DailyTask, resultTitle: String) -> String {
        if task.isDone { return "Logged \(DailyTaskRow.amountText(task.loggedCount)) to \(resultTitle)" }
        return task.isCounted ? "Each + logs 1 to \(resultTitle)" : "Counts \(DailyTaskRow.amountText(task.progressAmount)) toward \(resultTitle)"
    }

    private func entryField(symbol: String, placeholder: String, text: Binding<String>, accessibility: String, submit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .accessibilityHidden(true)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit(submit)
                .accessibilityLabel(accessibility)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .evidenceSafeGlass(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
    }

    private func addDone() {
        guard let task = timerVM.addDailyTask(title: doneTitle, projectID: projectID) else { return }
        withAnimation(.smooth(duration: 0.25)) { timerVM.setDailyTask(task, done: true, sessionID: sessionID) }
        doneTitle = ""
    }

    /// An open task for today on this block's project (replaces the carry-forward note).
    private func addNextStep() {
        guard let task = timerVM.addDailyTask(title: nextTitle, projectID: projectID) else { return }
        withAnimation(.smooth(duration: 0.25)) { lastNextStep = task.title }
        nextTitle = ""
    }
}
