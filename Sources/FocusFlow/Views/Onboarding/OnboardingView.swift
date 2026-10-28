import SwiftUI
import SwiftData

/// The welcome tour (onboarding design: docs/plans/2026-10-28-onboarding-design.md).
/// Five steps, one decision each, ending on a 5-minute start. Nothing is saved until the end;
/// Skip (or closing the window) only marks the tour done.
struct OnboardingView: View {
    static let size = CGSize(width: 640, height: 600)

    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]
    @Query private var allSettings: [AppSettings]

    @State private var step: OnboardingStep
    @State private var forward = true
    @State private var draft: OnboardingDraft
    @State private var prefilled: Bool
    @State private var finished = false
    /// Fixed for captures; nil = now.
    private let now: Date?

    init(step: OnboardingStep = .welcome, draft: OnboardingDraft? = nil, now: Date? = nil) {
        _step = State(initialValue: step)
        _draft = State(initialValue: draft ?? OnboardingDraft())
        _prefilled = State(initialValue: draft != nil)
        self.now = now
    }

    private var tint: Color { FFPalette.project(draft.color) }
    private var animated: Bool { !reduceMotion && !timerVM.isEvidenceMode }

    var body: some View {
        ZStack {
            OnboardingBackdrop(tint: tint, animated: animated)
            VStack(spacing: 0) {
                topBar
                ZStack {
                    stepContent
                        .id(step)
                        .transition(animated ? .asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ) : .opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 44)
                .padding(.top, 18)
                .clipped()
                bottomBar
            }
            if step == .start, animated {
                OnboardingConfetti(colors: [tint, .yellow, .pink, .mint, .orange, .accentColor])
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear {
            // The window can keep its state between openings; a finished tour starts over.
            if finished {
                finished = false
                step = .welcome
                prefilled = false
            }
            prefillIfNeeded()
        }
        .onDisappear {
            // Closing the window counts as skipping, so the tour doesn't come back every launch.
            if !finished { markDone() }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack {
            OnboardingProgress(step: step, tint: tint)
            HStack {
                Spacer()
                Button("Skip") { skipAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 30)
                    .contentShape(Rectangle())
                    .accessibilityHint("Closes the tour without saving")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(height: 44)
    }

    private var bottomBar: some View {
        HStack(spacing: FFSpace.m) {
            if let previous = step.previous {
                Button {
                    go(to: previous)
                } label: {
                    Label("Back", systemImage: "chevron.left").frame(minWidth: 64)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            }
            Spacer()
            switch step {
            case .goal:
                Button("Skip goal") {
                    draft.addsGoal = false
                    go(to: .coach)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                continueButton
            case .start:
                Button("Finish without starting") { finish(startMinutes: nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                Button {
                    finish(startMinutes: 5)
                } label: {
                    Label("Start 5 minutes", systemImage: "play.fill").frame(minWidth: 150)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            default:
                continueButton
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    private var continueButton: some View {
        Button {
            if step == .goal { draft.addsGoal = true }
            if let next = step.next { go(to: next) }
        } label: {
            Text(step == .welcome ? "Set me up · 1 min" : "Continue").frame(minWidth: 120)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!draft.canContinue(from: step))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: OnboardingWelcomeStep(tint: tint, animated: animated)
        case .priority: OnboardingPriorityStep(draft: $draft, projects: projects, tint: tint)
        case .goal: OnboardingGoalStep(draft: $draft, tint: tint, existingGoal: existingGoal, now: now ?? Date())
        case .coach: OnboardingCoachStep(draft: $draft, tint: tint)
        case .start: OnboardingStartStep(draft: $draft, tint: tint, animated: animated, now: now ?? Date())
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
        withAnimation(FFAnimation.gated(.spring(response: 0.45, dampingFraction: 0.86), reduceMotion: !animated)) {
            step = target
        }
    }

    private func prefillIfNeeded() {
        guard !prefilled else { return }
        prefilled = true
        draft = OnboardingDraft(projects: projects, settings: allSettings.first)
        if existingGoal != nil { draft.addsGoal = false }
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

    private func finish(startMinutes: Int?) {
        guard let settings = allSettings.first ?? timerVM.settings else { close(); return }
        finished = true
        let top = draft.commit(projects: projects, goals: goals, settings: settings, in: modelContext)
        timerVM.setNotchCompanionEnabled(draft.notchEnabled)
        close()
        if let startMinutes {
            _ = timerVM.startNextBlock(minutes: startMinutes, projectID: top?.id)
        }
    }

    private func close() {
        finished = true
        dismissWindow(id: "onboarding")
    }
}

// MARK: - Step header

private struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 1. Welcome

private struct OnboardingWelcomeStep: View {
    let tint: Color
    let animated: Bool

    @State private var shown = false

    private let promises: [(symbol: String, title: String, detail: String)] = [
        ("timer", "Blocks of 5, 15 or 25 minutes", "Starting is the hard part. Small blocks make it easy."),
        ("flag.checkered", "Your #1 first", "A goal with a deadline becomes one small step a day."),
        ("brain.head.profile", "A coach that learns", "It speaks up when you're free, and learns what gets you going."),
    ]

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeroRing(tint: tint, animated: animated)
                .padding(.top, 8)
            VStack(spacing: 8) {
                Text("Start small. Start now.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("FocusFlow helps you start the work that matters, one short block at a time.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            OnboardingCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(promises.enumerated()), id: \.offset) { index, promise in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: promise.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(tint)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(tint.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(promise.title).font(.system(size: 14, weight: .semibold))
                                Text(promise.detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown ? 0 : 8)
                        .animation(animated ? .smooth(duration: 0.5).delay(0.5 + Double(index) * 0.12) : nil, value: shown)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 12)
        .onAppear { shown = true }
    }
}

// MARK: - 2. What matters most

private struct OnboardingPriorityStep: View {
    @Binding var draft: OnboardingDraft
    let projects: [Project]
    let tint: Color

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "What matters most right now?",
                subtitle: "Pick the one thing you want more time for. It becomes your #1. You can add more later."
            )
            if !projects.isEmpty { existingRow }
            nameField
            if draft.existingProjectID == nil { presetRow }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingLabel("Kind")
                    HStack(spacing: 6) {
                        ForEach([ProjectArea.learning, .personal, .work], id: \.self) { area in
                            OnboardingChip(title: area.title, symbol: area.symbol, selected: draft.area == area, tint: tint) {
                                draft.setArea(area)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingLabel("Colour")
                    colourRow
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                OnboardingLabel("Time a day")
                HStack(spacing: 6) {
                    ForEach(OnboardingDraft.dailyMinuteOptions, id: \.self) { minutes in
                        OnboardingChip(title: FFFormat.duration(TimeInterval(minutes * 60)), selected: draft.dailyMinutes == minutes, tint: tint) {
                            draft.dailyMinutes = minutes
                        }
                    }
                }
                Text(draft.area.isOwnWork ? "This also becomes your daily focus goal." : "Work counts toward the total, not your own-work goal.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { if draft.trimmedName.isEmpty { nameFocused = true } }
    }

    private var existingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingLabel("Your projects")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(projects) { project in
                        OnboardingChip(title: project.name, symbol: project.icon ?? "folder.fill", selected: draft.existingProjectID == project.id,
                                       tint: FFPalette.project(project.color)) {
                            draft.select(project)
                        }
                    }
                    OnboardingChip(title: "New", symbol: "plus", selected: draft.existingProjectID == nil, tint: tint) {
                        draft.startNewProject()
                        nameFocused = true
                    }
                }
            }
        }
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Image(systemName: draft.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.gradient))
                .contentTransition(.symbolEffect(.replace))
            TextField("e.g. Interview prep", text: $draft.projectName)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .focused($nameFocused)
            Text("#1")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(tint.opacity(0.15)))
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous))
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingProjectPreset.all) { preset in
                OnboardingChip(title: preset.name, symbol: preset.icon, selected: draft.trimmedName == preset.name,
                               tint: FFPalette.project(preset.color)) {
                    draft.apply(preset)
                }
            }
        }
    }

    private var colourRow: some View {
        HStack(spacing: 3) {
            ForEach(OnboardingDraft.colors, id: \.self) { name in
                Button {
                    draft.color = name
                } label: {
                    Circle()
                        .fill(FFPalette.project(name))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(draft.color == name ? 0.9 : 0), lineWidth: 2))
                        .shadow(color: FFPalette.project(name).opacity(draft.color == name ? 0.6 : 0), radius: 4)
                        .frame(width: 20, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name.capitalized)
                .accessibilityAddTraits(draft.color == name ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.2), value: draft.color)
    }
}

// MARK: - 3. One result

private struct OnboardingGoalStep: View {
    @Binding var draft: OnboardingDraft
    let tint: Color
    let existingGoal: ProjectGoal?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "One result to aim for",
                subtitle: "Something you can count, with a date. The coach turns it into one small step a day."
            )
            if let existingGoal {
                Label("\(draft.trimmedName) already has “\(existingGoal.title)”. Add another, or skip.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                OnboardingLabel("What will you count?")
                TextField(OnboardingResultPreset.suggestions(for: draft.area).first?.title ?? "Sessions", text: $draft.resultTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous))
                HStack(spacing: 6) {
                    ForEach(OnboardingResultPreset.suggestions(for: draft.area)) { preset in
                        OnboardingChip(title: "\(preset.title) · \(preset.target)", selected: draft.trimmedResult == preset.title, tint: tint) {
                            draft.apply(preset)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingLabel("How many?")
                    counter
                }
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingLabel("By when?")
                    HStack(spacing: 6) {
                        ForEach(OnboardingDraft.deadlineOptions, id: \.days) { option in
                            OnboardingChip(title: option.label, selected: draft.deadlineDays == option.days, tint: tint) {
                                draft.deadlineDays = option.days
                            }
                        }
                    }
                }
            }
            paceCard
        }
    }

    private var counter: some View {
        HStack(spacing: 0) {
            stepButton("minus", delta: draft.resultTarget > 20 ? -5 : -1)
            Text("\(draft.resultTarget)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(draft.resultTarget)))
                .frame(width: 56)
            stepButton("plus", delta: draft.resultTarget >= 20 ? 5 : 1)
        }
        .frame(height: 32)
        .background(Capsule().fill(FFPalette.sectionFill))
        .overlay(Capsule().strokeBorder(FFPalette.hairline, lineWidth: 1))
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { draft.resultTarget = min(999, max(1, draft.resultTarget + delta)) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "More" : "Fewer")
    }

    private var paceCard: some View {
        OnboardingCard(padding: 14) {
            HStack(spacing: 16) {
                PaceSketch(tint: tint)
                    .frame(width: 84, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.trimmedResult.isEmpty ? "Your pace shows here" : draft.paceText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(draft.trimmedResult.isEmpty
                         ? "Type what you'll count, or tap a suggestion."
                         : "Goal: \(draft.goalTitle(now: now)). Today's step: \(draft.dailyQuota) \(draft.resultUnit(draft.dailyQuota)).")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .animation(.snappy(duration: 0.25), value: draft.paceText)
    }
}

/// The ideal line from zero to the target, with a dot where you start today.
private struct PaceSketch: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: size.height - 1))
            grid.addLine(to: CGPoint(x: size.width, y: size.height - 1))
            context.stroke(grid, with: .color(FFPalette.gridLine), lineWidth: 1)
            var line = Path()
            line.move(to: CGPoint(x: 4, y: size.height - 4))
            line.addLine(to: CGPoint(x: size.width - 4, y: 4))
            context.stroke(line, with: .color(tint.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
            context.fill(Path(ellipseIn: CGRect(x: 0, y: size.height - 8, width: 8, height: 8)), with: .color(tint))
            context.fill(Path(ellipseIn: CGRect(x: size.width - 9, y: 0, width: 9, height: 9)), with: .color(tint.opacity(0.35)))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 4. Your coach

private struct OnboardingCoachStep: View {
    @Binding var draft: OnboardingDraft
    let tint: Color

    private let styles: [(style: CoachStyle, symbol: String, detail: String)] = [
        (.gentle, "leaf.fill", "Kind nudges. Small steps."),
        (.data, "chart.bar.fill", "Numbers, pace and facts."),
        (.challenger, "flame.fill", "Direct. Holds you to it."),
    ]

    private let facts: [(symbol: String, text: String)] = [
        ("person.crop.circle.badge.checkmark", "Only speaks when you're at your desk"),
        ("timer", "Offers 5, 15 or 25 minutes"),
        ("bubble.left.and.text.bubble.right", "Asks why on a “not now”, and learns"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "How should your coach talk to you?",
                subtitle: "Here is what it would say to you today. You can change this in Settings."
            )
            HStack(spacing: 10) {
                ForEach(styles, id: \.style) { item in
                    styleCard(item.style, symbol: item.symbol, detail: item.detail)
                }
            }
            bubble
            HStack(alignment: .top, spacing: 0) {
                ForEach(facts, id: \.text) { fact in
                    VStack(spacing: 6) {
                        Image(systemName: fact.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(fact.text)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
    }

    private func styleCard(_ style: CoachStyle, symbol: String, detail: String) -> some View {
        let selected = draft.coachStyle == style
        return Button {
            withAnimation(.snappy(duration: 0.25)) { draft.coachStyle = style }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14))))
                    .symbolEffect(.bounce, value: selected)
                Text(style.displayName).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous).fill(selected ? tint.opacity(0.12) : FFPalette.sectionFill))
            .overlay(RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous).strokeBorder(selected ? tint.opacity(0.6) : FFPalette.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: FFRadius.section))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var bubble: some View {
        let preview = draft.coachPreview(draft.coachStyle)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.gradient))
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.hook).font(.system(size: 15, weight: .semibold))
                Text(preview.line).font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([5, 15, 25], id: \.self) { minutes in
                        Text("\(minutes) min")
                            .font(.system(size: 11.5, weight: minutes == 5 ? .semibold : .medium))
                            .foregroundStyle(minutes == 5 ? .white : .primary)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(Capsule().fill(minutes == 5 ? AnyShapeStyle(tint) : AnyShapeStyle(FFPalette.track)))
                    }
                    Text("Not now, because…").font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.leading, 4)
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
            .id(draft.coachStyle)
            .transition(.opacity.combined(with: .offset(y: 4)))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: FFRadius.hero, bottomTrailingRadius: FFRadius.hero, topTrailingRadius: FFRadius.hero, style: .continuous)
            .fill(FFPalette.sectionFill))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: FFRadius.hero, bottomTrailingRadius: FFRadius.hero, topTrailingRadius: FFRadius.hero, style: .continuous)
            .strokeBorder(FFPalette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(preview.hook) \(preview.line)")
    }
}

// MARK: - 5. First block

private struct OnboardingStartStep: View {
    @Binding var draft: OnboardingDraft
    let tint: Color
    let animated: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "Your first block is 5 minutes away.",
                subtitle: "Starting is the habit. Everything else follows."
            )
            OnboardingCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingNotchPreview(tint: tint, enabled: draft.notchEnabled, animated: animated)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show FocusFlow around the notch").font(.system(size: 13.5, weight: .semibold))
                            Text("Hover it to start, pause or log progress without opening anything.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Toggle("Show FocusFlow around the notch", isOn: $draft.notchEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(tint)
                    }
                }
            }
            OnboardingCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow(symbol: draft.icon, title: draft.trimmedName.isEmpty ? "No #1 yet" : draft.trimmedName,
                               detail: "#1 · \(draft.area.title) · \(FFFormat.duration(TimeInterval(draft.dailyMinutes * 60))) a day")
                    if draft.hasGoal {
                        summaryRow(symbol: "flag.checkered", title: draft.goalTitle(now: now), detail: "Today's step: \(draft.dailyQuota) \(draft.resultUnit(draft.dailyQuota))")
                    }
                    summaryRow(symbol: "brain.head.profile", title: "\(draft.coachStyle.displayName) coach", detail: draft.coachPreview(draft.coachStyle).hook)
                }
            }
            HStack(spacing: 8) {
                Text("⌃⌥Space")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(FFPalette.track))
                Text("starts a 5-minute block from anywhere. Everything else lives in the menu bar icon.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
