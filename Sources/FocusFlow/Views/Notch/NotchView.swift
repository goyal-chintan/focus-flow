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
        case overtime
        case onBreak(paused: Bool)
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
    var verdict: String?
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
    /// Today's reminder line (idle).
    var reminder: DailyReminderLine? = nil
    /// The coach's learned block size (`startLadderRecommendation`), marked with a sparkle.
    var suggestedMinutes: Int = CoachBlockSizeLadder.defaultMinutes
    /// Your regular length (`TimerViewModel.regularMinutes`): the prominent start, as everywhere else.
    var regularMinutes: Int = CoachBlockSizeLadder.defaultMinutes
    /// The next block size up (5 → 15 → 25) the running block can grow to; nil hides the button.
    var growToMinutes: Int? = nil

    var goalFraction: Double { goalTarget > 0 ? min(1, goalDone / goalTarget) : 0 }
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
        case .idle:
            if snapshot.coachHook != nil {
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
        case .overtime:
            wingText(snapshot.time, color: .orange)
        case .onBreak(let paused):
            wingText(snapshot.time, color: paused ? .green.opacity(0.55) : .green)
        case .idle:
            if snapshot.coachHook != nil {
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
        case .idle: idleExpanded
        case .focusing, .paused: focusExpanded
        case .overtime: overtimeExpanded
        case .onBreak(let paused): breakExpanded(paused: paused)
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
                if let intent = snapshot.intent, !intent.isEmpty {
                    Text(intent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            ProgressLine(progress: snapshot.progress, tint: tint)
            taskLine(tint: tint)
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
                if let result = snapshot.quickResult {
                    NotchButton(title: "\(result.title) +1", symbol: "arrow.up.circle.fill", prominent: true, tint: tint) {
                        actions.logResult(result.id)
                    }
                    .help("\(Int(result.done)) of \(Int(result.target)) · log one more")
                }
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
            if let lever = snapshot.lever {
                Text("Next: \(lever.action)").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 8) {
                NotchButton(title: "Start next block", symbol: "play.fill", prominent: true, tint: .green, action: actions.skipBreak)
                NotchButton(title: paused ? "Resume break" : "Pause break", symbol: paused ? "play" : "pause", action: actions.toggleBreak)
                Spacer(minLength: 0)
            }
        }
    }

    private var idleExpanded: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let reminder = snapshot.reminder {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: reminder.isOwn ? "heart.fill" : (reminder.isQuestion ? "questionmark" : "quote.opening"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange.opacity(0.85))
                        .accessibilityHidden(true)
                    Text(reminder.text)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(reminder.attribution)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Reminder: \(reminder.text), \(reminder.attribution)")
            }
            HStack(alignment: .center, spacing: 18) {
                GoalRing(fraction: snapshot.goalFraction, done: snapshot.goalDone, target: snapshot.goalTarget, label: snapshot.goalLabel)
                VStack(alignment: .leading, spacing: 6) {
                    if let hook = snapshot.coachHook {
                        Text(hook)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    Text(snapshot.lever == nil ? "NEXT BLOCK" : "TODAY'S LEVER")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(snapshot.lever?.action ?? (snapshot.projectName.map { "Start on \($0)" } ?? "Start a small block"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(snapshot.lever.map { "\($0.goalTitle) · \($0.reason)" } ?? "Small starts count.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
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
            taskLine(tint: FFPalette.project(snapshot.projectColor))
            if let verdict = snapshot.verdict {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    Text(verdict)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Button(action: actions.openGoals) {
                        Text("Goals").font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FFPalette.accent)
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                }
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
    var toggleBreak: () -> Void = {}
    var start: (Int) -> Void = { _ in }
    var logResult: (UUID) -> Void = { _ in }
    var openGoals: () -> Void = {}
    /// Ticks the task, or adds 1 to a counted one.
    var tickTask: (UUID) -> Void = { _ in }
    var undoTask: () -> Void = {}
    /// Overtime: open the block-end window to log the block.
    var log: () -> Void = {}
}

// MARK: - Pieces

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
