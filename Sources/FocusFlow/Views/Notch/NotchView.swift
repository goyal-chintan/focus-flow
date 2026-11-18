import SwiftUI
import SwiftData

/// Shared between the controller (which owns the window) and the view (which draws the island).
@MainActor
@Observable
final class NotchState {
    var expanded = false
    /// The notch's size (or the virtual notch on a screen without one).
    var notchSize = CGSize(width: 190, height: 32)
    var hasHardwareNotch = true
    /// Called by the view when the pointer enters or leaves the island.
    @ObservationIgnored var onHover: (Bool) -> Void = { _ in }
    /// Called by the view on a click in the compact state.
    @ObservationIgnored var onTapCompact: () -> Void = {}
    /// Height of the open island, measured from its content (no empty band at the bottom).
    var expandedHeight: CGFloat = 200
    @ObservationIgnored var onExpandedHeight: (CGFloat) -> Void = { _ in }
    /// The logged item whose label is being typed; the panel takes the keyboard meanwhile.
    var labelingEntryID: UUID?
    var labelDraft = ""
    @ObservationIgnored var onBeginLabeling: () -> Void = {}
    /// Ends typing; `save` writes the draft as the item's label.
    @ObservationIgnored var onEndLabeling: (_ save: Bool) -> Void = { _ in }

    /// Starts typing a label for one item; a label already open is saved first.
    func beginLabeling(_ id: UUID, draft: String) {
        onEndLabeling(true)
        labelDraft = draft
        labelingEntryID = id
        onBeginLabeling()
    }
}

/// One item logged in the running block ("Two Sum", 10:42), shown in the notch with a delete.
struct NotchLogItem: Identifiable, Equatable {
    let id: UUID
    let resultTitle: String
    /// What you called it; nil until you name it.
    let label: String?
    let at: Date
}

/// The island's outline: flat top flush with the screen edge, small concave "ears" where it
/// meets the menu bar, rounded bottom corners. Animates between compact and expanded.
struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set { earRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let ear = min(earRadius, rect.width / 4)
        let bottom = min(bottomRadius, (rect.height - ear) / 2, (rect.width - 2 * ear) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear), control: CGPoint(x: rect.minX + ear, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// What the island shows, derived from the timer and the day (pure inputs for previews and tests).
struct NotchSnapshot {
    enum Mode: Equatable {
        case idle
        case focusing
        case paused
        /// A block finished and is still counting up.
        case overtime
        case onBreak(paused: Bool)
        /// A break finished and is running over. Not `.overtime`: that one is a block's.
        case breakOver

        /// Both overtime kinds arrive as `.idle` + `isOvertime`; `isBreakOvertime` splits them.
        static func from(state: TimerState, isOvertime: Bool, isBreakOvertime: Bool, isBreakPaused: Bool) -> Mode {
            switch state {
            case .idle, .focusing:
                guard isOvertime else { return state == .idle ? .idle : .focusing }
                return isBreakOvertime ? .breakOver : .overtime
            case .paused: return .paused
            case .onBreak: return .onBreak(paused: isBreakPaused)
            }
        }
    }

    var mode: Mode
    var time: String
    var progress: Double
    var projectName: String?
    var projectColor: String?
    var intent: String?
    /// Own-work (or all) focus today and the daily goal.
    var goalDone: TimeInterval
    var goalTarget: TimeInterval
    var goalLabel: String
    var lever: DailyLever?
    /// The coach wants a start (prompt waiting).
    var coachHook: String?
    /// The running block's project has a key result to +1.
    var quickResult: (id: UUID, title: String, done: Double, target: Double)?
    /// Today's tasks (daily tasks design §2): counts, and the task to tick next
    /// (the block's own task while focusing).
    var tasks: DailyTaskStats? = nil
    var nextTask: (id: UUID, title: String)? = nil
    /// The next task is counted: logged so far and today's number ("1 of 3"); its button adds 1.
    var nextTaskCount: (logged: Double, target: Double)? = nil
    /// What the last tick or +1 logged, for a few seconds.
    var receipt: String? = nil
    /// The coach's learned block size (`startLadderRecommendation`), marked with a sparkle.
    var suggestedMinutes: Int = CoachBlockSizeLadder.defaultMinutes
    /// Your regular length (`TimerViewModel.regularMinutes`): the prominent start, as everywhere else.
    var regularMinutes: Int = CoachBlockSizeLadder.defaultMinutes
    /// The next block size up (5 → 15 → 25) the running block can grow to; nil hides the button.
    var growToMinutes: Int? = nil
    /// Everything logged in the running block, newest first.
    var blockLog: [NotchLogItem] = []
    /// The +1 number's count today (all blocks).
    var quickResultToday: Double? = nil
    /// A block cut short by a crash or quit, waiting to be resumed (idle only).
    var recovery: NotchRecovery? = nil

    var goalFraction: Double { goalTarget > 0 ? min(1, goalDone / goalTarget) : 0 }

    /// Coach v8 §3.6: one next action, the lever or the task, never both.
    var next: CalmSurfaces.NotchNext {
        CalmSurfaces.notchNext(
            inBlock: mode == .focusing || mode == .paused,
            hasTask: nextTask != nil || receipt != nil,
            tasksPlanned: tasks?.planned ?? 0,
            hasLever: lever != nil,
            hasResult: quickResult != nil
        )
    }

    /// The "Next: …" line on a break: the task, else the lever.
    var nextLine: String? {
        switch next {
        case .task: nextTask?.title
        case .lever: lever?.action
        case .result, .none: nil
        }
    }
}

/// The interrupted block offered for resuming, worded once for the notch and the popover banner.
struct NotchRecovery: Equatable {
    var title: String
    var detail: String
    var ago: String
    /// The interrupted block's project colour (the Resume button's tint).
    var color: String?

    static func make(_ recovery: CrashRecoveryState, projectName: String?, projectColor: String?, now: Date) -> NotchRecovery {
        let remaining = max(0, Int(recovery.remainingSeconds))
        let left = String(format: "%d:%02d left", remaining / 60, remaining % 60)
        let total = Int(recovery.totalSeconds / 60)
        let minutesAgo = Int(now.timeIntervalSince(recovery.checkpointDate) / 60)
        let label = recovery.customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotchRecovery(
            title: projectName ?? ((label?.isEmpty ?? true) ? "Focus" : label!),
            detail: "\(total)-min block · \(left)\(recovery.isPaused ? " · paused" : "")",
            ago: minutesAgo < 1 ? "just now" : "\(minutesAgo)m ago",
            color: projectColor
        )
    }
}

struct NotchView: View {
    let state: NotchState
    let snapshot: NotchSnapshot
    var actions = NotchActions()

    /// 5 · 15 · 25, plus your regular length when it is another size.
    private var startSizes: [Int] {
        CoachBlockSizeLadder.sizes.contains(snapshot.regularMinutes)
            ? CoachBlockSizeLadder.sizes : (CoachBlockSizeLadder.sizes + [snapshot.regularMinutes]).sorted()
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    private var compactSize: CGSize {
        CGSize(width: state.notchSize.width + 2 * NotchGeometry.wingWidth, height: state.notchSize.height)
    }

    private var expandedSize: CGSize {
        CGSize(
            width: max(NotchGeometry.expandedSize.width, compactSize.width),
            height: min(NotchGeometry.expandedSize.height + state.notchSize.height, max(state.notchSize.height + 80, state.expandedHeight))
        )
    }

    var body: some View {
        let size = state.expanded ? expandedSize : compactSize
        let ear: CGFloat = state.expanded ? 14 : 8
        ZStack(alignment: .top) {
            NotchShape(earRadius: ear, bottomRadius: state.expanded ? 28 : 11)
                .fill(Color.black)
                .shadow(color: .black.opacity(state.expanded ? 0.45 : 0), radius: 18, y: 8)
            if state.expanded {
                expandedContent
                    .padding(.horizontal, ear + 22)
                    .padding(.top, state.notchSize.height + 12)
                    .padding(.bottom, 20)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard abs(height - state.expandedHeight) > 0.5 else { return }
                        state.expandedHeight = height
                        state.onExpandedHeight(height)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(spring.delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            } else {
                compactContent
                    .padding(.horizontal, ear)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(NotchShape(earRadius: ear, bottomRadius: state.expanded ? 28 : 11))
        .onHover { state.onHover($0) }
        .onTapGesture { if !state.expanded { state.onTapCompact() } }
        .animation(spring, value: state.expanded)
        .onChange(of: snapshot.mode) { _, mode in
            // The block ended or went on a break while a label was being typed: keep what was typed.
            if mode != .focusing, mode != .paused { state.onEndLabeling(true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("FocusFlow")
    }

    // MARK: Compact

    private var compactContent: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: NotchGeometry.wingWidth - 8, alignment: .leading)
                .padding(.leading, 8)
            Color.clear.frame(width: state.notchSize.width)
            rightWing
                .frame(width: NotchGeometry.wingWidth - 8, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(height: state.notchSize.height)
    }

    @ViewBuilder
    private var leftWing: some View {
        switch snapshot.mode {
        case .focusing, .paused:
            MiniRing(progress: snapshot.progress, color: FFPalette.project(snapshot.projectColor), symbol: snapshot.mode == .paused ? "pause.fill" : nil)
        case .overtime:
            MiniRing(progress: 1, color: .orange, symbol: "checkmark")
        case .onBreak:
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
        case .breakOver:
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        case .idle:
            if snapshot.recovery != nil {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Block interrupted")
            } else if snapshot.coachHook != nil {
                BreathingDot(color: .orange)
            } else {
                MiniRing(progress: snapshot.goalFraction, color: snapshot.goalFraction >= 1 ? .green : FFPalette.accent, symbol: nil)
            }
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        switch snapshot.mode {
        case .focusing:
            wingText(snapshot.time, color: .white)
        case .paused:
            wingText(snapshot.time, color: .white.opacity(0.55))
        case .overtime, .breakOver:
            wingText(snapshot.time, color: .orange)
        case .onBreak(let paused):
            wingText(snapshot.time, color: paused ? .green.opacity(0.55) : .green)
        case .idle:
            if snapshot.recovery != nil {
                wingText("Resume?", color: .orange)
            } else if snapshot.coachHook != nil {
                wingText("Start?", color: .orange)
            } else {
                wingText(FFFormat.duration(snapshot.goalDone), color: .white.opacity(0.85))
            }
        }
    }

    private func wingText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    // MARK: Expanded

    @ViewBuilder
    private var expandedContent: some View {
        switch snapshot.mode {
        case .idle:
            if let recovery = snapshot.recovery { recoveryExpanded(recovery) } else { idleExpanded }
        case .focusing, .paused: focusExpanded
        case .overtime: overtimeExpanded
        case .onBreak(let paused): breakExpanded(paused: paused)
        case .breakOver: breakOverExpanded
        }
    }

    private var focusExpanded: some View {
        let tint = FFPalette.project(snapshot.projectColor)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                projectChip(tint: tint)
                Spacer(minLength: 8)
                Text(snapshot.mode == .paused ? "PAUSED" : "IN FOCUS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(snapshot.mode == .paused ? .white.opacity(0.5) : tint)
            }
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(snapshot.time)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                if let intent = CalmSurfaces.notchIntent(snapshot.intent, taskTitle: snapshot.next == .task ? snapshot.nextTask?.title : nil) {
                    Text(intent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            ProgressLine(progress: snapshot.progress, tint: tint)
            if snapshot.next == .task {
                taskLine(tint: tint)
            }
            if snapshot.quickResult != nil || !snapshot.blockLog.isEmpty {
                solvedSection(tint: tint)
            }
            HStack(spacing: 8) {
                if snapshot.mode == .paused {
                    NotchButton(title: "Resume", symbol: "play.fill", prominent: true, tint: tint, action: actions.resume)
                } else {
                    NotchButton(title: "Pause", symbol: "pause.fill", action: actions.pause)
                }
                if let grow = snapshot.growToMinutes {
                    NotchButton(title: "Make it \(grow)m", symbol: "plus") { actions.setLength(grow) }
                        .help("Grow this block to \(grow) minutes and use \(grow) for the next blocks")
                }
                NotchButton(title: "Finish", symbol: "checkmark", action: actions.finish)
                Spacer(minLength: 0)
            }
        }
    }

    private var overtimeExpanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                projectChip(tint: FFPalette.project(snapshot.projectColor))
                Spacer()
                Text("BLOCK DONE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.orange)
            }
            Text(snapshot.time)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
            Text("Block done. Log it, then keep going or rest.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                // Same verbs, same order as the popover (vocabulary audit 2026-10-30).
                NotchButton(title: "Log this block", symbol: "checkmark.circle", prominent: true, tint: .orange, action: actions.log)
                NotchButton(title: "Break 5 min", symbol: "cup.and.saucer.fill", action: actions.takeBreak)
                NotchButton(title: "Keep going", symbol: "forward.fill", action: actions.keepGoing)
                NotchButton(title: "Done for today", symbol: "stop.fill", action: actions.end)
                Spacer(minLength: 0)
            }
        }
    }

    private func breakExpanded(paused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(paused ? "BREAK · PAUSED" : "BREAK").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.green)
            Text(snapshot.time)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            if let next = snapshot.nextLine {
                Text("Next: \(next)").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            HStack(spacing: 8) {
                NotchButton(title: "Start next block", symbol: "play.fill", prominent: true, tint: .green, action: actions.skipBreak)
                NotchButton(title: paused ? "Resume break" : "Pause break", symbol: paused ? "play" : "pause", action: actions.toggleBreak)
                Spacer(minLength: 0)
            }
        }
    }

    /// The break ran over: the same two answers as the popover, never a block's "Keep going".
    private var breakOverExpanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BREAK OVER").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.orange)
            Text(snapshot.time)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .accessibilityLabel("Break ran \(snapshot.time.dropFirst()) over")
            if let next = snapshot.nextLine {
                Text("Next: \(next)").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            HStack(spacing: 8) {
                NotchButton(title: "Start next block", symbol: "play.fill", prominent: true, tint: .green, action: actions.startAfterBreak)
                NotchButton(title: "Done for today", symbol: "stop.fill", action: actions.end)
                Spacer(minLength: 0)
            }
        }
    }

    /// After a crash or quit mid-block: the block that was running, with Resume and Discard, as in
    /// the popover's banner. It replaces the idle start until it is answered.
    private func recoveryExpanded(_ recovery: NotchRecovery) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("BLOCK INTERRUPTED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.orange)
                Spacer(minLength: 8)
                Text(recovery.ago)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recovery.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(recovery.detail)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                NotchButton(title: "Resume", symbol: "play.fill", prominent: true, tint: FFPalette.project(recovery.color), action: actions.resumeRecovery)
                    .accessibilityLabel("Resume interrupted block")
                NotchButton(title: "Discard", symbol: "xmark", action: actions.discardRecovery)
                    .accessibilityLabel("Discard interrupted block")
                Spacer(minLength: 0)
            }
        }
    }

    /// Idle (coach v8 §3.6): one ring, one next action (the lever or the task, never both) and
    /// the start sizes. No quote and no totals line: Today holds those.
    private var idleExpanded: some View {
        let showsLever = snapshot.next == .lever
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                GoalRing(fraction: snapshot.goalFraction, done: snapshot.goalDone, target: snapshot.goalTarget, label: snapshot.goalLabel)
                VStack(alignment: .leading, spacing: 6) {
                    if let hook = snapshot.coachHook {
                        Text(hook)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    Text(showsLever ? "TODAY'S LEVER" : "NEXT BLOCK")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(showsLever ? (snapshot.lever?.action ?? "") : (snapshot.projectName.map { "Start on \($0)" } ?? "Start a small block"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        ForEach(startSizes, id: \.self) { minutes in
                            let isCoachAsk = minutes == snapshot.suggestedMinutes && minutes != snapshot.regularMinutes
                            NotchButton(title: "\(minutes) min", symbol: isCoachAsk ? "sparkle" : "play.fill", prominent: minutes == snapshot.regularMinutes, tint: FFPalette.project(snapshot.projectColor)) {
                                actions.start(minutes)
                            }
                            .help(isCoachAsk ? "The coach's suggested size" : "Start \(minutes) minutes")
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            if snapshot.next == .task {
                taskLine(tint: FFPalette.project(snapshot.projectColor))
            }
        }
    }

    /// "○ Next task · 2/5 tasks" with a tick; hidden without a plan. In a block, only the block's
    /// own task is offered; a block without one shows just the count.
    @ViewBuilder
    private func taskLine(tint: Color) -> some View {
        if let stats = snapshot.tasks, stats.planned > 0 {
            HStack(spacing: 8) {
                if let receipt = snapshot.receipt {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text(receipt)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Button("Undo", action: actions.undoTask)
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                } else if let task = snapshot.nextTask {
                    Button {
                        actions.tickTask(task.id)
                    } label: {
                        Group {
                            if let count = snapshot.nextTaskCount {
                                ZStack {
                                    Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
                                    Circle()
                                        .trim(from: 0, to: count.target > 0 ? min(1, count.logged / count.target) : 0)
                                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Image(systemName: "plus").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                }
                                .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(snapshot.nextTaskCount != nil ? "Add 1 to “\(task.title)”" : "Mark “\(task.title)” done")
                    .accessibilityLabel(snapshot.nextTaskCount != nil ? "Add 1 to \(task.title)" : "Mark \(task.title) done")
                    Text(task.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if let count = snapshot.nextTaskCount {
                        Text("\(DailyTaskReceipt.number(count.logged)) of \(DailyTaskReceipt.number(count.target))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                } else if stats.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.green)
                        .frame(width: 30, height: 30)
                    Text("Today's list is done.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text("Today's tasks")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Text("\(stats.done)/\(stats.planned) tasks")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(stats.isComplete ? .green : tint)
                    .contentTransition(.numericText())
            }
            .padding(.trailing, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
        }
    }

    /// "PROBLEMS SOLVED · 2 this block" with +1, then each item this block logged (newest first)
    /// with its time, its label and a delete, so a +1 is never silent and a wrong one can go.
    private func solvedSection(tint: Color) -> some View {
        let shown = Array(snapshot.blockLog.prefix(3))
        let title = snapshot.quickResult?.title ?? snapshot.blockLog.first?.resultTitle ?? "Logged"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Text(snapshot.blockLog.isEmpty ? "none yet this block" : "\(snapshot.blockLog.count) this block")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.blockLog.isEmpty ? .white.opacity(0.45) : tint)
                    .contentTransition(.numericText())
                Spacer(minLength: 6)
                if let result = snapshot.quickResult {
                    Text("\(KeyResultRow.number(snapshot.quickResultToday ?? 0)) today · \(KeyResultRow.number(result.done)) of \(KeyResultRow.number(result.target))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    NotchButton(title: "1", symbol: "plus", prominent: true, tint: tint) {
                        state.onEndLabeling(true)
                        guard let id = actions.logResult(result.id) else { return }
                        state.beginLabeling(id, draft: "")
                    }
                    .help("Log one more \(result.title), then name it (optional)")
                }
            }
            ForEach(shown) { item in
                logRow(item, tint: tint)
            }
            if snapshot.blockLog.count > shown.count {
                Text("+\(snapshot.blockLog.count - shown.count) earlier this block")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
        .animation(.easeOut(duration: 0.18), value: snapshot.blockLog)
    }

    private func logRow(_ item: NotchLogItem, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
                .frame(width: 20)
                .accessibilityHidden(true)
            if state.labelingEntryID == item.id {
                NotchLabelField(state: state, tint: tint)
            } else {
                Button {
                    state.beginLabeling(item.id, draft: item.label ?? "")
                } label: {
                    Text(item.label ?? "Add a label")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(item.label == nil ? .white.opacity(0.4) : .white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.label == nil ? "Name what you solved" : "Rename")
            }
            Text(item.at, format: .dateTime.hour().minute())
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
            Button {
                if state.labelingEntryID == item.id { state.onEndLabeling(false) }
                actions.deleteEntry(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this one (logged by mistake)")
            .accessibilityLabel("Remove \(item.label ?? item.resultTitle) logged at \(item.at.formatted(date: .omitted, time: .shortened))")
        }
        .frame(height: 28)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func projectChip(tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(snapshot.projectName ?? "Focus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(.white.opacity(0.1)))
    }
}

/// What the island's buttons do (the controller wires them to `TimerViewModel`).
struct NotchActions {
    var pause: () -> Void = {}
    var resume: () -> Void = {}
    var setLength: (Int) -> Void = { _ in }
    var finish: () -> Void = {}
    var keepGoing: () -> Void = {}
    var takeBreak: () -> Void = {}
    var end: () -> Void = {}
    var skipBreak: () -> Void = {}
    /// A break that ran over: start the next block.
    var startAfterBreak: () -> Void = {}
    var toggleBreak: () -> Void = {}
    var start: (Int) -> Void = { _ in }
    /// +1 on a number; returns the entry it logged (to label it).
    var logResult: (UUID) -> UUID? = { _ in nil }
    /// Removes one logged item.
    var deleteEntry: (UUID) -> Void = { _ in }
    /// Ticks the task, or adds 1 to a counted one.
    var tickTask: (UUID) -> Void = { _ in }
    var undoTask: () -> Void = {}
    /// Overtime: open the block-end window to log the block.
    var log: () -> Void = {}
    /// The block a crash or quit cut short: pick it up, or let it go.
    var resumeRecovery: () -> Void = {}
    var discardRecovery: () -> Void = {}
}

// MARK: - Pieces

/// "What was it?" typed straight into the island; Return saves, Esc leaves it unnamed.
private struct NotchLabelField: View {
    @Bindable var state: NotchState
    let tint: Color
    @FocusState private var focused: Bool

    var body: some View {
        TextField("What was it? (optional) ↩", text: $state.labelDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .tint(tint)
            .focused($focused)
            .onSubmit { state.onEndLabeling(true) }
            .onExitCommand { state.onEndLabeling(false) }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tint.opacity(0.6), lineWidth: 1))
            .task {
                // The panel becomes key in the same turn; focus once it has.
                try? await Task.sleep(for: .milliseconds(30))
                focused = true
            }
    }
}

private struct MiniRing: View {
    let progress: Double
    let color: Color
    let symbol: String?

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(1, max(0.001, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let symbol {
                Image(systemName: symbol).font(.system(size: 7, weight: .black)).foregroundStyle(color)
            }
        }
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: 0.4), value: progress)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent")
    }
}

private struct BreathingDot: View {
    let color: Color
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(on ? 0.9 : 0.2), radius: on ? 6 : 1)
            .scaleEffect(on ? 1.15 : 0.85)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatCount(6, autoreverses: true)) { on = true }
            }
            .accessibilityLabel("The coach is waiting")
    }
}

private struct GoalRing: View {
    let fraction: Double
    let done: TimeInterval
    let target: TimeInterval
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(
                        AngularGradient(colors: [FFPalette.accent, fraction >= 1 ? .green : FFPalette.accent.opacity(0.75)], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(FFFormat.duration(done))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("of \(FFFormat.duration(target))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 84, height: 84)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(FFFormat.duration(done)) of \(FFFormat.duration(target))")
    }
}

private struct ProgressLine: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(4, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 1), value: progress)
    }
}

/// A capsule button tuned for the black island: 30 pt tall, readable, with a hover lift.
struct NotchButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var tint: Color = FFPalette.accent
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(hovering ? 0.2 : 0.12)))
            )
            .brightness(prominent && hovering ? 0.08 : 0)
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(title)
    }
}
