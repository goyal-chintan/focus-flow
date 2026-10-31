import SwiftUI
import SwiftData

/// The welcome tour (onboarding v2: docs/plans/2026-10-31-onboarding-v2-design.md §3.5).
/// Full screen. The coach meets you, then asks for your direction, how to measure it, your
/// rhythm and how to coach you. Your goal card builds up on the right as you answer. It ends on a
/// start only inside one of your windows; otherwise it plans the next one. Nothing is saved
/// until the end; Skip only marks the tour done.
struct OnboardingView: View {
    /// Captures render at this size; live, the tour fills the screen.
    static let size = CGSize(width: 1440, height: 900)

    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]
    @Query private var allSettings: [AppSettings]

    @State private var step: OnboardingStep
    @State private var forward = true
    @State private var draft: OnboardingDraft
    @State private var prefilled: Bool
    @State private var finished = false
    @State private var reaction = 0
    /// The card's trip to the menu bar at the end.
    @State private var flyingHome = false
    private let fixedNow: Date?
    private let onClose: () -> Void

    init(step: OnboardingStep = .meet, draft: OnboardingDraft? = nil, now: Date? = nil, onClose: @escaping () -> Void = {}) {
        _step = State(initialValue: step)
        _draft = State(initialValue: draft ?? OnboardingDraft(now: now ?? Date()))
        _prefilled = State(initialValue: draft != nil)
        self.fixedNow = now
        self.onClose = onClose
    }

    private var now: Date { fixedNow ?? Date() }
    private var animated: Bool { !reduceMotion && !timerVM.isEvidenceMode }
    /// The tour runs again from Settings once it was finished.
    private var isRerun: Bool { allSettings.first?.onboardingCompletedAt != nil }
    private var cardColor: String { draft.markColor(avoiding: projects.map(\.color)) }
    /// The coach's colour until you name a goal; then your goal's colour.
    private var tint: Color { draft.trimmedName.isEmpty ? FFPalette.accent : FFPalette.project(cardColor) }

    /// Discrete choices the card reacts to (not every keystroke).
    private var reactionKey: String {
        [draft.area.rawValue, cardColor, draft.windows.map(\.label).joined(), "\(draft.dailyMinutes)", "\(draft.resultTarget)",
         "\(draft.deadlineDays)", draft.coachStyle.rawValue, "\(draft.tracksNumber)", draft.existingProjectID?.uuidString ?? ""]
            .joined(separator: "|")
    }

    var body: some View {
        ZStack {
            // Over the behind-window blur live; solid in captures, where the blur can't render.
            (timerVM.isEvidenceMode ? FFPalette.windowBackground : FFPalette.windowBackground.opacity(0.55))
                .ignoresSafeArea()
            if step == .meet {
                OnboardingMeetStep(tint: tint, animated: animated, isRerun: isRerun) { go(to: .what) }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                conversation
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) { skipButton }
        .frame(minWidth: 1100, minHeight: 720)
        .onChange(of: reactionKey) { reaction += 1 }
        .onAppear { prefillIfNeeded() }
        .onDisappear {
            if !finished { markDone() }
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        HStack(alignment: .center, spacing: 72) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    stepPane
                        .id(step)
                        .transition(animated ? .asymmetric(
                            insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
                            removal: .offset(x: forward ? -28 : 28).combined(with: .opacity)
                        ) : .opacity)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                footer
            }
            .frame(width: 540)
            .frame(maxHeight: 640)
            .opacity(flyingHome ? 0 : 1)
            stage
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepPane: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center, spacing: 14) {
                OnboardingCoachAvatar(tint: tint, size: 40, speaking: step.rawValue)
                Text(stepLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .onboardingMaterialize(0, animated: animated)
            VStack(alignment: .leading, spacing: 10) {
                Text(coachLine)
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingMaterialize(0.05, animated: animated)
                Text(coachDetail)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingMaterialize(0.1, animated: animated)
            }
            Group {
                switch step {
                case .meet: EmptyView()
                case .what: OnboardingWhatControls(draft: $draft, projects: projects, tint: tint)
                case .measure: OnboardingMeasureControls(draft: $draft, tint: tint, existingGoal: existingGoal, now: now)
                case .when: OnboardingWhenControls(draft: $draft, tint: tint)
                case .plan: OnboardingPlanControls(draft: $draft, tint: tint, now: now)
                }
            }
            .onboardingMaterialize(0.16, animated: animated)
        }
    }

    private var stepLabel: String {
        let label = switch step {
        case .meet, .what: "Your direction"
        case .measure: "Your measure"
        case .when: "Your rhythm"
        case .plan: "Your coach"
        }
        return "\(label) · \(step.rawValue) of \(OnboardingStep.allCases.count - 1)"
    }

    private var coachLine: String {
        switch step {
        case .meet, .what: "What do you want to make happen in the next few months?"
        case .measure: "How will we know it's working?"
        case .when: "When are you at your best?"
        case .plan: "How should I talk to you?"
        }
    }

    private var coachDetail: String {
        switch step {
        case .meet, .what: "Pick one goal. It becomes your #1, and it gets my full attention."
        case .measure: "Give me something to count and a date. I'll track it and turn it into a small step each day."
        case .when: "I'll only speak up in these times, and never more than 3 times a day."
        case .plan:
            switch draft.ending(now: now) {
            case .startNow(let window): "You're in your \(OnboardingDraft.label(window)) time right now. Let's use it."
            case .planAt(let date): "I'll be on screen \(OnboardingDraft.when(date, now: now)). All you have to do is start."
            case .none: "Add a time in Settings → Coach whenever you're ready."
            }
        }
    }

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 20) {
            OnboardingHeroCard(draft: draft, step: step, color: cardColor, now: now, animated: animated, reaction: reaction)
            if step == .plan {
                coachBubble
                    .transition(animated
                                ? .asymmetric(insertion: .scale(scale: 0.85, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -20)),
                                              removal: .opacity)
                                : .opacity)
            }
        }
        .scaleEffect(flyingHome ? 0.05 : (step == .plan ? 0.88 : 1), anchor: .center)
        .offset(flyingHome ? CGSize(width: 320, height: -520) : .zero)
        .opacity(flyingHome ? 0 : 1)
        .animation(OnboardingMotion.settle, value: step)
        .frame(width: 400)
    }

    private var coachBubble: some View {
        CoachStylePreviewCard(
            style: draft.coachStyle,
            projectName: draft.trimmedName.isEmpty ? "your #1" : draft.trimmedName,
            lever: draft.stepTitle,
            suggestedMinutes: CoachBlockSizeLadder.sizes.contains(timerVM.regularMinutes) ? timerVM.regularMinutes : 25
        )
        .padding(16)
        .frame(width: 380)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
    }

    // MARK: Chrome

    private var skipButton: some View {
        Button("Skip") { skipAll() }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            // Below the menu bar.
            .padding(.top, 48)
            .padding(.trailing, 32)
            .accessibilityHint("Closes the tour without saving")
            .opacity(flyingHome ? 0 : 1)
    }

    private var footer: some View {
        GlassEffectContainer {
            HStack(spacing: FFSpace.m) {
                if let previous = step.previous, previous != .meet {
                    Button {
                        go(to: previous)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 18, height: 22)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Back")
                }
                if step == .plan {
                    planButtons
                } else {
                    OnboardingPrimaryButton(title: "Continue", systemImage: "arrow.right", tint: tint) {
                        if let next = step.next { go(to: next) }
                    }
                    .disabled(!draft.canContinue(from: step))
                }
                Spacer(minLength: 0)
            }
        }
        .opacity(flyingHome ? 0 : 1)
    }

    /// Inside a window: start now. Otherwise: plan the next window, with "Start now" beside it.
    @ViewBuilder
    private var planButtons: some View {
        switch draft.ending(now: now) {
        case .startNow:
            OnboardingPrimaryButton(title: "Start now · \(timerVM.regularMinutes) min", systemImage: "play.fill", tint: tint) { finish(start: true) }
            Button("Finish") { finish(start: false) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        case .planAt(let date):
            OnboardingPrimaryButton(title: "Done · see you at \(FFFormat.clock(date))", systemImage: "checkmark", tint: tint) { finish(start: false) }
            Button("Start now") { finish(start: true) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        case .none:
            OnboardingPrimaryButton(title: "Done", systemImage: "checkmark", tint: tint) { finish(start: false) }
        }
    }

    /// The picked project's active goal, if it already has one.
    private var existingGoal: ProjectGoal? {
        guard let id = draft.existingProjectID else { return nil }
        return goals.first { $0.projectID == id && $0.status == .active }
    }

    // MARK: Flow

    private func go(to target: OnboardingStep) {
        forward = target > step
        withAnimation(animated ? OnboardingMotion.settle : .easeInOut(duration: 0.2)) {
            step = target
        }
    }

    private func prefillIfNeeded() {
        guard !prefilled else { return }
        prefilled = true
        draft = OnboardingDraft(projects: projects, settings: allSettings.first, now: now)
        // A #1 that already has a goal keeps it; the tour doesn't add a second by default.
        if existingGoal != nil { draft.tracksNumber = false }
    }

    private func skipAll() {
        markDone()
        close()
    }

    private func markDone() {
        guard let settings = allSettings.first, settings.onboardingCompletedAt == nil else { return }
        settings.onboardingCompletedAt = Date()
        try? modelContext.save()
    }

    private func finish(start: Bool) {
        guard !flyingHome else { return }
        guard let settings = allSettings.first ?? timerVM.settings else { close(); return }
        finished = true
        let at = Date()
        // A plan only when you're not already in a window: the window's own prompt covers that.
        var planStart: Date?
        if case .planAt(let date) = draft.ending(now: at) { planStart = date }
        let top = draft.commit(projects: projects, goals: goals, settings: settings, in: modelContext,
                               now: at, planStart: planStart, blockMinutes: timerVM.regularMinutes)
        let minutes = timerVM.regularMinutes
        let done = {
            close()
            if start { _ = timerVM.startNextBlock(minutes: minutes, projectID: top?.id) }
        }
        guard animated else { done(); return }
        // The card flies up toward the menu bar, where your coach lives from now on.
        withAnimation(.spring(response: 0.7, dampingFraction: 1)) { flyingHome = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: done)
    }

    private func close() {
        finished = true
        onClose()
    }
}

// MARK: - Shared

/// The one prominent action on a screen, in the goal's colour.
private struct OnboardingPrimaryButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(tint)
        .controlSize(.extraLarge)
        .keyboardShortcut(.defaultAction)
        .animation(OnboardingMotion.settle, value: tint)
    }
}

// MARK: - 0. Meet

/// The coach introduces itself: who it is and the three things it will do for you.
private struct OnboardingMeetStep: View {
    let tint: Color
    let animated: Bool
    let isRerun: Bool
    let begin: () -> Void

    private let promises: [(symbol: String, title: String, detail: String)] = [
        ("waveform.path.ecg", "I learn when you work best.", "Your rhythm, not a fixed schedule."),
        ("bell.badge", "I show up at the right moment.", "With one small, concrete step, and a reason."),
        ("chart.line.uptrend.xyaxis", "I keep track of your goal for you.", "So you always know if you're on pace."),
    ]

    var body: some View {
        VStack(spacing: 34) {
            OnboardingCoachAvatar(tint: tint, size: 84, speaking: 0)
                .onboardingMaterialize(0, animated: animated)
            VStack(spacing: 12) {
                Text(isRerun ? "Let's set your direction again." : "Hi. I'm your coach.")
                    .font(.system(size: 48, weight: .bold))
                    .tracking(-1.2)
                    .onboardingMaterialize(0.15, animated: animated)
                Text("I help you make real progress on what matters most to you.")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .onboardingMaterialize(0.3, animated: animated)
            }
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(promises.enumerated()), id: \.offset) { index, promise in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: promise.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promise.title).font(.system(size: 17, weight: .semibold))
                            Text(promise.detail).font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                    }
                    .onboardingMaterialize(0.6 + Double(index) * 0.25, animated: animated)
                }
            }
            .padding(.top, 6)
            VStack(spacing: 10) {
                OnboardingPrimaryButton(title: "Let's set your direction", systemImage: "arrow.right", tint: tint, action: begin)
                Text("About a minute. You can change everything later.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .onboardingMaterialize(1.45, animated: animated)
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 1. Direction

private struct OnboardingWhatControls: View {
    @Binding var draft: OnboardingDraft
    let projects: [Project]
    let tint: Color

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                OnboardingTextField(placeholder: "Your goal, in your words", text: $draft.projectName, size: 19)
                    .focused($nameFocused)
                    .onChange(of: draft.projectName) { draft.nameChanged() }
                GlassEffectContainer {
                    FlowRow {
                        if !projects.isEmpty {
                            ForEach(projects) { project in
                                OnboardingPill(title: project.name, symbol: project.icon ?? "folder.fill", selected: draft.existingProjectID == project.id,
                                               tint: FFPalette.project(project.color)) { draft.select(project) }
                            }
                        }
                        ForEach(OnboardingProjectPreset.all) { preset in
                            OnboardingPill(title: preset.name, symbol: preset.icon, selected: draft.existingProjectID == nil && draft.trimmedName == preset.name,
                                           tint: FFPalette.project(preset.color)) {
                                withAnimation(OnboardingMotion.settle) { draft.apply(preset) }
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                OnboardingCaption("Why does this matter to you?")
                OnboardingTextField(placeholder: draft.whyHint, text: $draft.why, size: 15, weight: .medium)
                Text("I'll remind you of this on hard days.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                OnboardingCaption("Counts as")
                GlassEffectContainer {
                    HStack(spacing: 6) {
                        ForEach([ProjectArea.learning, .personal, .work], id: \.self) { area in
                            OnboardingPill(title: area.title, symbol: area.symbol, selected: draft.area == area, tint: tint) {
                                withAnimation(OnboardingMotion.settle) { draft.setArea(area) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { if draft.trimmedName.isEmpty { nameFocused = true } }
    }
}

// MARK: - 2. Measure

private struct OnboardingMeasureControls: View {
    @Binding var draft: OnboardingDraft
    let tint: Color
    let existingGoal: ProjectGoal?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if draft.tracksNumber { numberFields.transition(.opacity.combined(with: .offset(y: -8))) } else { laterRow }
            VStack(alignment: .leading, spacing: 10) {
                OnboardingCaption("And the very first step?")
                OnboardingTextField(placeholder: draft.firstStepSuggestions.first ?? "Sketch the plan", text: $draft.firstStep, size: 15, weight: .medium)
                GlassEffectContainer {
                    FlowRow {
                        ForEach(draft.firstStepSuggestions, id: \.self) { suggestion in
                            OnboardingPill(title: suggestion, selected: draft.trimmedFirstStep == suggestion, tint: tint) {
                                withAnimation(OnboardingMotion.settle) { draft.firstStep = suggestion }
                            }
                        }
                    }
                }
            }
        }
    }

    private var numberFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                OnboardingCaption("What to count")
                Spacer()
                Button("Decide later") { withAnimation(OnboardingMotion.settle) { draft.tracksNumber = false } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 30)
            }
            OnboardingTextField(placeholder: draft.resultSuggestions.first?.title ?? "Sessions", text: $draft.resultTitle, size: 15, weight: .medium)
            GlassEffectContainer {
                FlowRow {
                    ForEach(draft.resultSuggestions) { preset in
                        OnboardingPill(title: preset.title, selected: draft.trimmedResult == preset.title, tint: tint) {
                            withAnimation(OnboardingMotion.settle) { draft.apply(preset) }
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("\(draft.resultTarget)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(draft.resultTarget)))
                        .frame(minWidth: 44, alignment: .trailing)
                    Stepper("How many", value: $draft.resultTarget.animation(OnboardingMotion.settle), in: 1...999,
                            step: draft.resultTarget >= 20 ? 5 : 1)
                        .labelsHidden()
                }
                GlassEffectContainer {
                    HStack(spacing: 6) {
                        ForEach(OnboardingDraft.deadlineOptions, id: \.days) { option in
                            OnboardingPill(title: "in \(option.label)", selected: draft.deadlineDays == option.days, tint: tint) {
                                withAnimation(OnboardingMotion.settle) { draft.deadlineDays = option.days }
                            }
                        }
                    }
                }
            }
            if !draft.trimmedResult.isEmpty {
                Label("That's \(draft.paceText). Today's step: \(draft.dailyQuota) \(draft.resultUnit(draft.dailyQuota)).", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
        }
    }

    private var laterRow: some View {
        HStack(spacing: 12) {
            Text(existingGoal.map { "Your goal already has “\($0.title)”." } ?? "No number yet. I'll ask again once you've started.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
            Button("Track a number") { withAnimation(OnboardingMotion.settle) { draft.tracksNumber = true } }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }
}

// MARK: - 3. Rhythm

private struct OnboardingWhenControls: View {
    @Binding var draft: OnboardingDraft
    let tint: Color

    @State private var editingCustom = false
    @State private var customStart = 21 * 60
    @State private var customEnd = 23 * 60

    private var customWindows: [CoachOwnWorkWindow] {
        draft.windows.filter { window in !OnboardingWindowPreset.all.contains { $0.window == window } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                OnboardingCaption("Usually free")
                GlassEffectContainer {
                    FlowRow {
                        ForEach(OnboardingWindowPreset.all) { preset in
                            let selected = draft.windows.contains(preset.window)
                            OnboardingPill(title: preset.title, detail: OnboardingDraft.label(preset.window), symbol: preset.symbol,
                                           selected: selected, tint: tint) {
                                withAnimation(OnboardingMotion.lively) { draft.toggle(preset.window) }
                            }
                            .disabled(!selected && !draft.canAddWindow)
                        }
                        ForEach(customWindows) { window in
                            OnboardingPill(title: OnboardingDraft.label(window), symbol: "xmark", selected: true, tint: tint) {
                                withAnimation(OnboardingMotion.lively) { draft.toggle(window) }
                            }
                            .accessibilityLabel("Remove \(OnboardingDraft.label(window))")
                        }
                        if draft.canAddWindow {
                            OnboardingPill(title: "Other", symbol: "plus", selected: editingCustom, tint: tint) {
                                withAnimation(OnboardingMotion.settle) { editingCustom.toggle() }
                            }
                        }
                    }
                }
                if editingCustom { customEditor.transition(.opacity.combined(with: .offset(y: -6))) }
            }
            VStack(alignment: .leading, spacing: 10) {
                OnboardingCaption("Time a day for your goal")
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        ForEach(OnboardingDraft.dailyMinuteOptions, id: \.self) { minutes in
                            OnboardingPill(title: FFFormat.duration(TimeInterval(minutes * 60)), selected: draft.dailyMinutes == minutes, tint: tint) {
                                withAnimation(OnboardingMotion.settle) { draft.dailyMinutes = minutes }
                            }
                        }
                    }
                }
                if draft.exceedsWindows {
                    Label("More than the \(FFFormat.duration(TimeInterval(draft.windowMinutes * 60))) these times hold. Add a time or lower it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(FFPalette.atRisk)
                        .transition(.opacity)
                }
            }
        }
    }

    private var customEditor: some View {
        HStack(spacing: 8) {
            DatePicker("From", selection: minuteBinding($customStart), displayedComponents: .hourAndMinute).labelsHidden()
            Text("to").foregroundStyle(.secondary)
            DatePicker("To", selection: minuteBinding($customEnd), displayedComponents: .hourAndMinute).labelsHidden()
            Button("Add") {
                withAnimation(OnboardingMotion.lively) {
                    draft.addCustom(CoachOwnWorkWindow(startMinute: customStart, endMinute: max(customEnd, customStart + 15)))
                    editingCustom = false
                }
            }
            .buttonStyle(.glass)
        }
        .font(.system(size: 13))
        .fixedSize()
    }

    private func minuteBinding(_ minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: minute.wrappedValue, to: Calendar.current.startOfDay(for: Date())) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

// MARK: - 4. Coach

private struct OnboardingPlanControls: View {
    @Binding var draft: OnboardingDraft
    let tint: Color
    let now: Date

    /// The coach's promises, in its own words, from your answers.
    private var promises: [(symbol: String, text: String)] {
        var rows: [(String, String)] = []
        switch draft.ending(now: now) {
        case .planAt(let date): rows.append(("clock.fill", "I'll be on screen \(OnboardingDraft.when(date, now: now)), with your first step."))
        case .startNow: rows.append(("bolt.fill", "We start now, while you're in your time."))
        case .none: break
        }
        if draft.hasGoal {
            rows.append(("chart.line.uptrend.xyaxis", "I'll track \(draft.resultTarget) \(draft.trimmedResult.lowercased()) by \(draft.deadline(from: now).formatted(.dateTime.day().month(.abbreviated))), \(PaceFormat.rate(draft.perDay)), and tell you if you fall behind."))
        }
        rows.append(("waveform.path.ecg", "I'll learn what gets you started, and adapt."))
        rows.append(("keyboard", "\(CoachStarterBlock.hotkeyKeys) \(CoachStarterBlock.hotkeyAction)."))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(CoachStyle.allCases, id: \.self) { style in
                        OnboardingPill(title: style.displayName, symbol: OnboardingDraft.symbol(style), selected: draft.coachStyle == style, tint: tint) {
                            withAnimation(OnboardingMotion.settle) { draft.coachStyle = style }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                OnboardingCaption("Here's my plan for you")
                ForEach(Array(promises.enumerated()), id: \.offset) { _, promise in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: promise.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 20)
                        Text(promise.text)
                            .font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Layout

/// Wraps its children onto new lines, left-aligned.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: [Int] = []
        var x: CGFloat = 0
        var height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.isEmpty, x + size.width > width {
                rows.append((current, x - spacing, height))
                current = []
                x = 0
                height = 0
            }
            current.append(index)
            x += size.width + spacing
            height = max(height, size.height)
        }
        if !current.isEmpty { rows.append((current, x - spacing, height)) }
        return rows
    }
}
