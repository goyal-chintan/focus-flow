import SwiftUI
import SwiftData

/// Coach v6 §3.5: the first thing in Insights. What the coach noticed in your blocks and breaks,
/// one sentence each, plus whatever it is unsure about with a one-tap answer in place.
/// Read-only in `body`: patterns are computed from queries, answers run in button actions.
struct CoachNoticedSection: View {
    let days: Int
    let now: Date

    @Environment(TimerViewModel.self) private var timerVM
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query(sort: \BreakLearningEvent.createdAt) private var breakEvents: [BreakLearningEvent]
    @Query private var allSettings: [AppSettings]
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]

    var body: some View {
        let patterns = daysPattern() + computePatterns()
        let questions = questionsToShow()
        FFSection("What the coach noticed", subtitle: "From your last \(days) days of blocks and breaks. These are what the coach acts on.") {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                if patterns.isEmpty && questions.isEmpty {
                    FFEmptyState(
                        systemImage: "sparkles",
                        message: "Not enough blocks yet",
                        detail: "After about 8 blocks the coach says when you start, how long your breaks run and which block length you finish."
                    )
                }
                ForEach(questions, id: \.id) { question in
                    questionCard(question)
                }
                ForEach(patterns) { pattern in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: pattern.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.title).ffText(.headline)
                            Text(pattern.sentence)
                                .ffText(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func questionCard(_ question: CoachQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(question.hook, systemImage: "questionmark.bubble")
                .ffText(.headline)
            Text(question.detail)
                .ffText(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(Array(question.choices.enumerated()), id: \.element.id) { index, choice in
                    if index == 0 {
                        Button(choice.title) { answer(question, choice) }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button(choice.title) { answer(question, choice) }
                            .buttonStyle(.glass)
                    }
                }
            }
            .controlSize(.regular)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func answer(_ question: CoachQuestion, _ choice: CoachQuestionChoice) {
        switch question {
        case .windowFit:
            if let answer = CoachQuestion.WindowFitAnswer(rawValue: choice.id), let settings = allSettings.first {
                timerVM.applyWindowFitAnswer(answer, settings: settings)
            }
        case .projectArea(let id, _, _):
            if let area = ProjectArea(rawValue: choice.id) { timerVM.setProjectArea(id, area: area) }
        case .naturalLength:
            timerVM.applyNaturalLengthAnswer(choice)
        case .dayType(let day, _, _):
            if let type = DayType(rawValue: choice.id) { timerVM.setDayType(day, type: type) }
        }
    }

    // MARK: Data

    /// Coach v8: the kind of days you had and whether days off were planned (phase 3 turns this
    /// into the Your week page).
    private func daysPattern() -> [CoachPattern] {
        guard let sentence = DayLedgerSummary.sentence(timerVM.dayLedger(days: min(days, 28), now: now)) else { return [] }
        return [CoachPattern(kind: .days, symbol: "calendar", title: "Your days", sentence: sentence)]
    }

    private var ownWorkConfigured: Bool { GoalDataBuilder.ownWorkConfigured(projects) }

    private func computePatterns() -> [CoachPattern] {
        let since = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let configured = ownWorkConfigured
        let blocks = sessions.filter { $0.type == .focus && $0.startedAt >= since && $0.endedAt != nil }.map { session in
            CoachPatterns.Block(
                start: session.startedAt,
                end: session.endedAt ?? session.startedAt,
                plannedMinutes: Int(session.duration / 60),
                focusedSeconds: session.actualDuration,
                completed: session.completed,
                ownWork: !configured || CoachHistoryReader.isOwnWork(session.project)
            )
        }
        let breaks = breakEvents.filter { $0.createdAt >= since }.map {
            CoachPatterns.Break(suggestedMinutes: $0.suggestedMinutes, actualSeconds: $0.actualBreakSeconds, overrunSeconds: $0.overrunSeconds, returnedToFocus: $0.returnedToFocus)
        }
        let cycleSessions = sessions.filter { $0.startedAt >= since }.compactMap { session -> CoachCycleStats.Session? in
            guard let end = session.endedAt else { return nil }
            return CoachCycleStats.Session(isFocus: session.type == .focus, start: session.startedAt, end: end,
                                           plannedSeconds: session.duration, pausedSeconds: session.totalPausedSeconds)
        }
        let estimate = CoachCycleExperiment.estimate(
            timerVM.cycleDecisions(), starts: sessions.filter { $0.type == .focus }.map(\.startedAt), now: now
        )
        return CoachPatterns.compute(blocks: blocks, breaks: breaks, declared: allSettings.first?.coachOwnWorkWindows ?? [],
                                     cycle: CoachCycleStats.compute(cycleSessions), returnEstimate: estimate)
    }

    /// Questions answered here in place: the window fit (from the same 28 days the coach uses)
    /// and a busy project with no area. Pure reads; nothing is written while drawing.
    private func questionsToShow() -> [CoachQuestion] {
        var questions: [CoachQuestion] = []
        if let day = timerVM.dayTypeQuestion(now: now) { questions.append(day) }
        let declared = allSettings.first?.coachOwnWorkWindows ?? []
        let since = now.addingTimeInterval(-TimeInterval(CoachWindowFit.lookbackDays) * 86_400)
        let configured = ownWorkConfigured
        let recent = sessions.filter { $0.type == .focus && $0.startedAt >= since }
        let ownStarts = recent.filter { !configured || CoachHistoryReader.isOwnWork($0.project) }.map(\.startedAt)
        let fit = CoachWindowFit.compute(startDates: ownStarts, declared: declared)
        if fit.isMismatch(declared: declared), !timerVM.keepsDeclaredWindows(now: now) {
            questions.append(.windowFit(fit, declared: declared))
        }
        let counts = Dictionary(grouping: recent.compactMap { $0.project?.id }, by: { $0 }).mapValues(\.count)
        if let project = CoachQuestion.unclassifiedProject(projects.map {
            (id: $0.id, name: $0.name, hasArea: $0.areaRaw != nil, isWork: $0.areaRaw != nil && $0.area == .work, blocks: counts[$0.id] ?? 0)
        }) {
            questions.append(project)
        }
        let regular = timerVM.regularMinutes
        let recentSessions = sessions.filter { $0.startedAt >= now.addingTimeInterval(-30 * 86_400) }.compactMap { session -> CoachCycleStats.Session? in
            guard let end = session.endedAt else { return nil }
            return CoachCycleStats.Session(isFocus: session.type == .focus, start: session.startedAt, end: end,
                                           plannedSeconds: session.duration, pausedSeconds: session.totalPausedSeconds)
        }
        if let minutes = CoachNaturalLength.suggestion(recentSessions, regularMinutes: regular), !timerVM.isCoachQuestionSnoozed("natural_length", now: now) {
            questions.append(.naturalLength(minutes: minutes, regular: regular))
        }
        return questions
    }
}
