import SwiftUI

// Parts of the welcome tour (onboarding v2 §3.4): the card you build, the day dial, pills and
// the materialize entrance. Colour comes only from the chosen project, and the dial's sky track
// encodes the time of day.

enum OnboardingMotion {
    /// Critically damped: the default for anything that just changes.
    static let settle = Animation.spring(response: 0.45, dampingFraction: 1)
    /// A little life for physical changes (arcs drawing, the card reacting to a choice).
    static let lively = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// The text entrance.
    static let materialize = Animation.spring(response: 0.55, dampingFraction: 1)
}

// MARK: - Materialize

/// Opacity, blur and a small rise together, so text arrives like a material rather than a fade.
/// Reduce Motion (or a capture) shows it at once.
struct OnboardingMaterialize: ViewModifier {
    let delay: Double
    let animated: Bool

    @State private var shown = false

    func body(content: Content) -> some View {
        let visible = shown || !animated
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 8)
            .offset(y: visible ? 0 : 10)
            .onAppear {
                guard animated else { return }
                withAnimation(OnboardingMotion.materialize.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func onboardingMaterialize(_ delay: Double = 0, animated: Bool) -> some View {
        modifier(OnboardingMaterialize(delay: delay, animated: animated))
    }
}

// MARK: - Pills

/// A capsule choice: `.glassProminent` in the project colour when selected, `.glass` otherwise.
struct OnboardingPill: View {
    let title: String
    var detail: String?
    var symbol: String?
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        if selected {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolEffect(.bounce, value: selected)
                }
                Text(title).font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 2)
            .frame(minHeight: 22)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A text field on a glass plate.
struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: weight))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Small tracked label over a group of controls.
struct OnboardingCaption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Day dial

/// A 24-hour dial: a faint sky track (night, dawn, noon, dusk), your times drawn on as arcs in the
/// project colour, and a dot at now. Midnight is at the top.
struct OnboardingDayDial: View {
    let windows: [CoachOwnWorkWindow]
    let tint: Color
    let now: Date
    let active: Bool
    let centre: String
    let caption: String
    let animated: Bool

    static let sky: [Color] = [
        Color(red: 0.16, green: 0.20, blue: 0.42),  // 00 night
        Color(red: 0.96, green: 0.58, blue: 0.30),  // 06 dawn
        Color(red: 0.38, green: 0.68, blue: 0.98),  // 12 noon
        Color(red: 0.93, green: 0.45, blue: 0.55),  // 18 dusk
        Color(red: 0.16, green: 0.20, blue: 0.42),  // 24 night
    ]

    private let line: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .stroke(AngularGradient(colors: Self.sky, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        lineWidth: line)
                .opacity(active ? 0.28 : 0.12)
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                tick(hour)
            }
            if active {
                ForEach(windows) { window in
                    OnboardingDialArc(window: window, tint: tint, line: line, animated: animated)
                }
                nowDot
            }
            VStack(spacing: 0) {
                Text(centre)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .opacity(active ? 1 : 0.45)
        }
        .padding(line / 2)
        .animation(OnboardingMotion.lively, value: windows)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "Your times: \(windows.map(OnboardingDraft.label).joined(separator: ", ")). \(centre) \(caption)" : "Times not chosen yet")
    }

    private func tick(_ hour: Int) -> some View {
        GeometryReader { proxy in
            let radius = proxy.size.width / 2
            let angle = Angle.degrees(Double(hour) / 24 * 360 - 90)
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 1.5, height: 5)
                .rotationEffect(angle + .degrees(90))
                .position(x: radius + cos(angle.radians) * (radius - line - 5),
                          y: radius + sin(angle.radians) * (radius - line - 5))
        }
    }

    private var nowDot: some View {
        GeometryReader { proxy in
            let radius = proxy.size.width / 2
            let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
            let minute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            let angle = Angle.degrees(minute / 1440 * 360 - 90)
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 2)
                .position(x: radius + cos(angle.radians) * radius, y: radius + sin(angle.radians) * radius)
        }
        .accessibilityHidden(true)
    }
}

/// One window as an arc that draws itself on.
private struct OnboardingDialArc: View {
    let window: CoachOwnWorkWindow
    let tint: Color
    let line: CGFloat
    let animated: Bool

    @State private var drawn: CGFloat = 0

    var body: some View {
        let start = CGFloat(window.startMinute) / 1440
        let end = CGFloat(window.endMinute) / 1440
        Circle()
            .trim(from: start, to: start + (end - start) * (animated ? drawn : 1))
            .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .shadow(color: tint.opacity(0.5), radius: 4)
            .onAppear {
                guard animated else { return }
                withAnimation(OnboardingMotion.lively) { drawn = 1 }
            }
    }
}

// MARK: - The coach

/// The coach's face in the tour: one symbol in a solid disc. It bounces when the coach speaks.
struct OnboardingCoachAvatar: View {
    let tint: Color
    var size: CGFloat = 44
    let speaking: Int

    var body: some View {
        Image(systemName: "brain.head.profile")
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce, value: speaking)
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .shadow(color: tint.opacity(0.45), radius: size * 0.35, y: size * 0.12)
            .accessibilityHidden(true)
    }
}

/// A goal's progress: a ring at 0 that will fill as you log, with the count in the middle.
struct OnboardingGoalRing: View {
    let done: Int
    let target: Int
    let tint: Color
    let active: Bool

    var body: some View {
        ZStack {
            Circle().stroke(FFPalette.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: active ? max(0.02, CGFloat(done) / CGFloat(max(1, target))) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(active ? "\(done)" : "–")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(active ? "of \(target)" : "goal")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(target)))
            }
            .opacity(active ? 1 : 0.45)
        }
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "\(done) of \(target)" : "No goal number yet")
    }
}

// MARK: - The card

/// Your goal, built as you answer: the goal, its number, your rhythm and the first step.
/// Empty slots show what is still to come.
struct OnboardingHeroCard: View {
    let draft: OnboardingDraft
    let step: OnboardingStep
    let color: String
    let now: Date
    let animated: Bool
    /// Changes on every discrete choice, so the card answers with a small spring.
    let reaction: Int

    static let size = CGSize(width: 360, height: 548)

    @State private var pulse: CGFloat = 1
    /// The card's sheet: white in light mode, a lifted grey in dark mode.
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x2C2C2E, lightAlpha: 1, darkAlpha: 1)

    private var named: Bool { !draft.trimmedName.isEmpty }
    private var tint: Color { named ? FFPalette.project(color) : Color.secondary }
    private var measured: Bool { step >= .measure }
    private var hasWhen: Bool { step >= .when }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            whyLine
            divider
            goalSection
            divider
            whenSection
            divider
            stepSection
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        // Content, not a control: a solid lifted sheet, not glass (UI_DESIGN_GUIDE: glass on controls only).
        .background {
            let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
            shape.fill(Self.surface)
                .overlay(shape.fill(tint.opacity(named ? 0.07 : 0)))
        }
        .overlay {
            let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
            if named {
                // Light catching the top edge.
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            } else {
                shape.strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
            }
        }
        .shadow(color: named ? tint.opacity(0.35) : .black.opacity(0.12), radius: 44, y: 22)
        .scaleEffect(pulse)
        .onChange(of: reaction) {
            guard animated else { return }
            withAnimation(.snappy(duration: 0.12)) { pulse = 1.018 } completion: {
                withAnimation(.bouncy(duration: 0.45)) { pulse = 1 }
            }
        }
        .animation(OnboardingMotion.settle, value: color)
        .animation(OnboardingMotion.settle, value: named)
        .animation(OnboardingMotion.settle, value: step)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: named ? draft.icon : "sparkle")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(named ? Color.white : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: draft.area)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(named ? AnyShapeStyle(tint) : AnyShapeStyle(FFPalette.track)))
            VStack(alignment: .leading, spacing: 2) {
                Text(named ? draft.trimmedName : "Your goal")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(named ? .primary : .secondary)
                    .lineLimit(2)
                    .contentTransition(.interpolate)
                Text(named ? "\(draft.area.title) · your #1" : "Name it to begin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
            }
        }
    }

    @ViewBuilder
    private var whyLine: some View {
        if !draft.trimmedWhy.isEmpty {
            Text("“\(draft.trimmedWhy)”")
                .font(.system(size: 13.5, weight: .medium))
                .italic()
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(2)
                .transition(.opacity.combined(with: .offset(y: 4)))
        } else {
            skeleton(width: 190)
        }
    }

    private var divider: some View {
        Rectangle().fill(FFPalette.hairline).frame(height: 1)
    }

    private var goalSection: some View {
        HStack(spacing: 16) {
            OnboardingGoalRing(done: 0, target: draft.resultTarget, tint: tint, active: measured && draft.hasGoal)
                .frame(width: 84, height: 84)
                .animation(OnboardingMotion.lively, value: draft.hasGoal)
            VStack(alignment: .leading, spacing: 5) {
                OnboardingCaption("Goal")
                if measured && draft.hasGoal {
                    Text("\(draft.resultTarget) \(draft.trimmedResult.lowercased())")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .contentTransition(.numericText(value: Double(draft.resultTarget)))
                    Text("by \(draft.deadline(from: now).formatted(.dateTime.day().month(.abbreviated))) · \(PaceFormat.rate(draft.perDay))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text("I'll track this for you")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tint)
                } else if measured {
                    Text("You'll set it later").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    skeleton(width: 120)
                    skeleton(width: 80)
                }
            }
        }
    }

    private var whenSection: some View {
        HStack(spacing: 16) {
            OnboardingDayDial(
                windows: draft.windows,
                tint: tint,
                now: now,
                active: hasWhen && !draft.windows.isEmpty,
                centre: hasWhen ? FFFormat.duration(TimeInterval(draft.dailyMinutes * 60)) : "–",
                caption: "a day",
                animated: animated
            )
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 5) {
                OnboardingCaption("Rhythm")
                if hasWhen && !draft.windows.isEmpty {
                    ForEach(draft.windows) { window in
                        Text(OnboardingDraft.label(window))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .transition(.opacity.combined(with: .offset(x: -6)))
                    }
                    Text("\(FFFormat.duration(TimeInterval(draft.dailyMinutes * (draft.area == .work ? 5 : 7) * 60))) a week")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else {
                    skeleton(width: 90)
                    skeleton(width: 60)
                }
            }
        }
    }

    private var stepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingCaption("First step")
            if measured, let title = draft.stepTitle {
                HStack(alignment: .top, spacing: 10) {
                    OnboardingCheckCircle(tint: tint, animated: animated)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .contentTransition(.interpolate)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                skeleton(width: 160)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if step == .plan {
            HStack(spacing: 6) {
                Image(systemName: OnboardingDraft.symbol(draft.coachStyle))
                    .contentTransition(.symbolEffect(.replace))
                Text("\(draft.coachStyle.displayName) coach\(footerWhen)")
                    .contentTransition(.interpolate)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        } else {
            Label("Your #1", systemImage: "star.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var footerWhen: String {
        if case .planAt(let date) = draft.ending(now: now) { return " · \(OnboardingDraft.when(date, now: now))" }
        return ""
    }

    private func skeleton(width: CGFloat) -> some View {
        Capsule().fill(FFPalette.track).frame(width: width, height: 9).accessibilityHidden(true)
    }
}

/// A circle that draws itself, like a to-do waiting for its tick.
private struct OnboardingCheckCircle: View {
    let tint: Color
    let animated: Bool

    @State private var drawn: CGFloat = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: animated ? drawn : 1)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 17, height: 17)
            .padding(.top, 1)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeOut(duration: 0.5)) { drawn = 1 }
            }
            .accessibilityHidden(true)
    }
}
