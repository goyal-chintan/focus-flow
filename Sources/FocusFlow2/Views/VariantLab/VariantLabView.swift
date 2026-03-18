import SwiftUI
import AppKit
import Foundation

private struct VariantLabDecisionKey: Hashable {
    let component: VariantLabComponent
    let variant: VariantLabMenuVariant
}

private enum StudioMaterialProfile: String, CaseIterable, Identifiable {
    case crystal = "Crystal"
    case balanced = "Balanced"
    case frosted = "Frosted"

    var id: String { rawValue }
}

private enum VariantBackdropStyle: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case aurora = "Aurora"
    case contrast = "Contrast"

    var id: String { rawValue }
}

struct VariantLabView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var scenario: VariantLabScenario = .idle
    @State private var component: VariantLabComponent = .timerRing
    @State private var motionSpeed: VariantLabMotionSpeed = .x1
    @State private var backdropStyle: VariantBackdropStyle = .aurora
    @State private var showAllComponentSliders = true
    @State private var isExpanded = true
    @State private var hoverPreview = false
    @State private var pressPreview = false
    @State private var pressAmount: CGFloat = 0
    @State private var transitionStep = 0
    @State private var materialProfile: StudioMaterialProfile = .balanced
    @State private var materialOpacity: Double = 0.90
    @State private var highlightStrength: Double = 0.18
    @State private var motionIntensity: Double = 1.0
    @State private var ringScaleTuning: Double = 1.0
    @State private var ringStrokeTuning: Double = 1.0
    @State private var ringTextTuning: Double = 1.0
    @State private var buttonProminence: Double = 1.0
    @State private var buttonSecondaryOpacity: Double = 0.45
    @State private var buttonSpacingTuning: Double = 1.0
    @State private var glassEdgeStrength: Double = 1.0
    @State private var glassBloomStrength: Double = 1.0
    @State private var motionHoverTuning: Double = 1.0
    @State private var motionPressTuning: Double = 1.0
    @State private var motionDriftTuning: Double = 1.0

    @State private var roundName = "1"
    @State private var winnerByComponent: [VariantLabComponent: VariantLabMenuVariant] = Dictionary(
        uniqueKeysWithValues: VariantLabComponent.allCases.map { ($0, .variantA) }
    )

    @State private var ratingsByDecision: [VariantLabDecisionKey: [VariantLabCriterion: Int]] = Dictionary(
        uniqueKeysWithValues: VariantLabComponent.allCases.flatMap { component in
            VariantLabMenuVariant.allCases.map { variant in
                (VariantLabDecisionKey(component: component, variant: variant), defaultVariantLabRatings())
            }
        }
    )
    @State private var actionsByDecision: [VariantLabDecisionKey: VariantLabDecisionAction] = [:]
    @State private var notesByDecision: [VariantLabDecisionKey: String] = Dictionary(
        uniqueKeysWithValues: VariantLabComponent.allCases.flatMap { component in
            VariantLabMenuVariant.allCases.map { variant in
                (VariantLabDecisionKey(component: component, variant: variant), "")
            }
        }
    )

    @State private var statusMessage: String = ""
    @State private var latestLogURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpacing.md) {
                headerSection
                modeGuideSection
                guidanceSection
                controlsSection
                componentTuningSection
                comparisonLegendSection
                variantsSection
                finalizeSection
                workflowRulesSection
            }
            .padding(FFSpacing.lg)
        }
        .frame(minWidth: 1220, minHeight: 840)
        .background(labBackdrop)
    }

    private var headerSection: some View {
        ContentPanel(cornerRadius: FFRadius.hero, padding: FFSpacing.lg) {
            HStack(alignment: .top, spacing: FFSpacing.md) {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("FocusFlow 2 \u{00B7} Variant Lab")
                        .font(FFType.titleLarge)
                    Text("Variant-first design decisions. Compare A/B/C, tune component sliders, then lock one winner per component.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: FFSpacing.xs) {
                    Text("Round")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                    TextField("1", text: $roundName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            if !statusMessage.isEmpty {
                HStack(spacing: FFSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(statusMessage)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }
            }

            if let latestLogURL {
                HStack(spacing: FFSpacing.sm) {
                    Text("Log file:")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                    Text(latestLogURL.path)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([latestLogURL])
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.5))
                }
            }
        }
    }

    private var modeGuideSection: some View {
        ContentPanel(cornerRadius: FFRadius.card, padding: FFSpacing.md) {
            HStack(alignment: .top, spacing: FFSpacing.md) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Use Variant Lab for decisions")
                        .font(FFType.title)
                    Text("This is the primary screen: compare A/B/C, tune component sliders, save notes, and finalize winners.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Use Design Lab for advanced tokens")
                        .font(FFType.title)
                    Text("Design Lab is optional and best used after winner decisions are locked here.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                    Button("Open Design Lab (Advanced)") {
                        openWindow(id: "design-lab")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.5))
                }
            }
        }
    }

    private var controlsSection: some View {
        ContentPanel(cornerRadius: FFRadius.card) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .top, spacing: FFSpacing.md) {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Scenario")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                        Picker("Scenario", selection: $scenario) {
                            ForEach(VariantLabScenario.allCases) { scenario in
                                Text(scenario.displayName).tag(scenario)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(3)

                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Component")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                        Picker("Component", selection: $component) {
                            ForEach(VariantLabComponent.allCases) { component in
                                Text(component.rawValue).tag(component)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(2)

                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Animation Speed")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                        Picker("Animation Speed", selection: $motionSpeed) {
                            ForEach(VariantLabMotionSpeed.allCases) { speed in
                                Text(speed.rawValue).tag(speed)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Color.white.opacity(0.72))
                        .frame(width: 220)
                    }
                    .frame(width: 220, alignment: .leading)
                    .layoutPriority(1)
                }

                HStack(alignment: .center, spacing: FFSpacing.md) {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Backdrop")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                        Picker("Backdrop", selection: $backdropStyle) {
                            ForEach(VariantBackdropStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Color.white.opacity(0.72))
                        .frame(width: 280)
                    }

                    Toggle("Show all component sliders", isOn: $showAllComponentSliders)
                        .toggleStyle(.switch)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                        .tint(FFColor.focus.opacity(0.9))

                    Spacer()
                }

                HStack(spacing: FFSpacing.sm) {
                    Button(isExpanded ? "Close Preview" : "Open Preview") {
                        animate { isExpanded.toggle() }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.55))

                    Button("Hover Preview") {
                        triggerHoverPreview()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.55))

                    Button("Press Preview") {
                        triggerPressPreview()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.55))

                    Button("Transition") {
                        animate { transitionStep += 1 }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.55))

                    Spacer()

                    Text("State: \(scenario.displayName)")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var componentTuningSection: some View {
        ContentPanel(cornerRadius: FFRadius.card, padding: FFSpacing.md) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Component Sliders")
                        .font(FFType.title)
                    Text("Tune in one long list, then decide A/B/C for the current component only.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }

                if showAllComponentSliders || component == .effects {
                    sliderGroup(title: "Glass Effects") {
                        sliderRow("Material Profile") {
                            Picker("Material Profile", selection: $materialProfile) {
                                ForEach(StudioMaterialProfile.allCases) { profile in
                                    Text(profile.rawValue).tag(profile)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(Color.white.opacity(0.72))
                        }
                        sliderRow("Transparency", value: $materialOpacity, range: 0.72...1.0, step: 0.01)
                        sliderRow("Highlight", value: $highlightStrength, range: 0.08...0.30, step: 0.01)
                        sliderRow("Edge Strength", value: $glassEdgeStrength, range: 0.6...1.6, step: 0.05)
                        sliderRow("Glass Bloom", value: $glassBloomStrength, range: 0.6...1.6, step: 0.05)
                    }
                }

                if showAllComponentSliders || component == .timerRing {
                    sliderGroup(title: "Timer Ring") {
                        sliderRow("Ring Scale", value: $ringScaleTuning, range: 0.80...1.30, step: 0.02)
                        sliderRow("Ring Stroke", value: $ringStrokeTuning, range: 0.6...1.8, step: 0.05)
                        sliderRow("Timer Text", value: $ringTextTuning, range: 0.75...1.30, step: 0.02)
                    }
                }

                if showAllComponentSliders || component == .buttons {
                    sliderGroup(title: "Primary Buttons") {
                        sliderRow("Button Prominence", value: $buttonProminence, range: 0.75...1.30, step: 0.02)
                        sliderRow("Secondary Quietness", value: $buttonSecondaryOpacity, range: 0.22...0.72, step: 0.02)
                        sliderRow("Button Spacing", value: $buttonSpacingTuning, range: 0.75...1.40, step: 0.02)
                    }
                }

                if showAllComponentSliders || component == .motion {
                    sliderGroup(title: "Motion") {
                        sliderRow("Motion Intensity", value: $motionIntensity, range: 0.7...1.4, step: 0.05)
                        sliderRow("Hover Lift", value: $motionHoverTuning, range: 0.5...1.6, step: 0.05)
                        sliderRow("Press Depth", value: $motionPressTuning, range: 0.5...1.6, step: 0.05)
                        sliderRow("Drift Amount", value: $motionDriftTuning, range: 0.5...1.8, step: 0.05)
                    }
                }
            }
        }
    }

    private func sliderGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text(title)
                .font(FFType.meta)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(FFSpacing.sm)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: FFSpacing.sm) {
            Text(label)
                .font(FFType.meta)
                .frame(width: 150, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(.white.opacity(0.78))
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func sliderRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: FFSpacing.sm) {
            Text(label)
                .font(FFType.meta)
                .frame(width: 150, alignment: .leading)
            content()
        }
    }

    private var variantsSection: some View {
        let snapshot = scenario.snapshot(transitionStep: transitionStep)

        return LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 360), spacing: FFSpacing.md),
                GridItem(.flexible(minimum: 360), spacing: FFSpacing.md),
                GridItem(.flexible(minimum: 360), spacing: FFSpacing.md)
            ],
            alignment: .leading,
            spacing: FFSpacing.md
        ) {
            ForEach(VariantLabMenuVariant.allCases) { variant in
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    VariantPreviewCard(
                        variant: variant,
                        component: component,
                        scenario: scenario,
                        snapshot: snapshot,
                        isExpanded: isExpanded,
                        hoverPreview: hoverPreview,
                        pressAmount: pressAmount,
                        transitionStep: transitionStep,
                        animation: springAnimation,
                        materialProfile: materialProfile,
                        materialOpacity: materialOpacity,
                        highlightStrength: highlightStrength,
                        motionIntensity: motionIntensity,
                        ringScaleTuning: ringScaleTuning,
                        ringStrokeTuning: ringStrokeTuning,
                        ringTextTuning: ringTextTuning,
                        buttonProminence: buttonProminence,
                        buttonSecondaryOpacity: buttonSecondaryOpacity,
                        buttonSpacingTuning: buttonSpacingTuning,
                        glassEdgeStrength: glassEdgeStrength,
                        glassBloomStrength: glassBloomStrength,
                        motionHoverTuning: motionHoverTuning,
                        motionPressTuning: motionPressTuning,
                        motionDriftTuning: motionDriftTuning,
                        backdropStyle: backdropStyle
                    )

                    decisionPanel(for: variant, component: component)
                }
            }
        }
    }

    private var comparisonLegendSection: some View {
        ContentPanel(cornerRadius: FFRadius.card, padding: FFSpacing.md) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("What To Compare For \(component.rawValue)")
                    .font(FFType.title)
                ForEach(VariantLabMenuVariant.allCases) { variant in
                    Text("\(variant.rawValue): \(variant.subtitle(for: component))")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var finalizeSection: some View {
        ContentPanel(cornerRadius: FFRadius.card) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Component Finalization")
                    .font(FFType.title)

                Text("Pick one winner for the current component, then archive the other two. Each component keeps its own winner and notes.")
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)

                HStack(spacing: FFSpacing.md) {
                    Picker("Winner", selection: winnerBinding(for: component)) {
                        ForEach(VariantLabMenuVariant.allCases) { variant in
                            Text(variant.rawValue).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.white.opacity(0.72))
                    .frame(width: 220)

                    Button("Finalize \(component.rawValue) Winner") {
                        finalizeRound(for: component)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FFColor.focus)
                }

                HStack(spacing: FFSpacing.xs) {
                    ForEach(VariantLabComponent.allCases) { reviewComponent in
                        let selected = winnerByComponent[reviewComponent] ?? .variantA
                        Text("\(reviewComponent.rawValue): \(selected.rawValue)")
                            .font(FFType.meta)
                            .padding(.horizontal, FFSpacing.sm)
                            .padding(.vertical, FFSpacing.xxs)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    private var guidanceSection: some View {
        ContentPanel(cornerRadius: FFRadius.card, padding: FFSpacing.md) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("How To Use Variant Lab")
                    .font(FFType.title)
                Text("1. Select one Component tab and one Scenario.")
                    .font(FFType.meta)
                Text("2. Use Open/Hover/Press/Transition and Backdrop to inspect glass behavior.")
                    .font(FFType.meta)
                Text("3. Tune sliders for this component (or all components in one list).")
                    .font(FFType.meta)
                Text("4. Rate A, B, C separately, choose Keep/Reject/Needs tweak, add notes, and save each card.")
                    .font(FFType.meta)
                Text("5. Finalize winner for only the current component.")
                    .font(FFType.meta)
            }
        }
    }

    private var workflowRulesSection: some View {
        ContentPanel(cornerRadius: FFRadius.card) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Workflow Guardrails")
                    .font(FFType.title)

                Text("1. Keep exactly one winner per round")
                    .font(FFType.meta)
                Text("2. Max two rounds per surface before freeze")
                    .font(FFType.meta)
                Text("3. Only evolve the winner unless a blocker appears")
                    .font(FFType.meta)
                Text("4. Save notes every time you choose Keep/Reject/Needs tweak")
                    .font(FFType.meta)
            }
        }
    }

    private func decisionPanel(for variant: VariantLabMenuVariant, component: VariantLabComponent) -> some View {
        let decisionKey = VariantLabDecisionKey(component: component, variant: variant)

        return ContentPanel(cornerRadius: FFRadius.card, padding: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text(variant.title(for: component))
                        .font(FFType.title)
                    Text(variant.subtitle(for: component))
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }

                ForEach(VariantLabCriterion.allCases) { criterion in
                    HStack(spacing: FFSpacing.sm) {
                        Text(criterion.rawValue)
                            .font(FFType.meta)
                            .lineLimit(1)
                        Spacer()
                        Text("\(ratingValue(for: variant, criterion: criterion))/5")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 36)

                        Slider(
                            value: ratingBinding(for: variant, criterion: criterion),
                            in: 1...5,
                            step: 1
                        )
                        .frame(width: 140)
                        .tint(Color.white.opacity(0.76))
                    }
                }

                HStack(spacing: FFSpacing.xs) {
                    ForEach(VariantLabDecisionAction.allCases) { action in
                        let selected = actionsByDecision[decisionKey] == action
                        Button(action.rawValue) {
                            actionsByDecision[decisionKey] = action
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(selected ? actionColor(action) : .white.opacity(0.45))
                    }
                }

                TextField("Why this decision?", text: noteBinding(for: decisionKey), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)

                Button("Save Decision") {
                    saveDecision(for: variant, in: component)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(FFColor.success)
                .disabled(actionsByDecision[decisionKey] == nil)
            }
        }
    }

    private var labBackdrop: some View {
        ZStack {
            switch backdropStyle {
            case .studio:
                LinearGradient(
                    colors: [Color.black.opacity(0.30), Color.white.opacity(0.02), Color.black.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

            case .aurora:
                LinearGradient(
                    colors: [Color.black.opacity(0.30), Color.indigo.opacity(0.10), Color.teal.opacity(0.08), Color.black.opacity(0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

            case .contrast:
                LinearGradient(
                    colors: [Color.black.opacity(0.40), Color.black.opacity(0.26)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            if backdropStyle != .studio {
                RadialGradient(
                    colors: [Color.white.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 30,
                    endRadius: 360
                )
                .blendMode(.screen)
            }

            if backdropStyle == .contrast {
                VStack(spacing: 16) {
                    ForEach(0..<18, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.05) : Color.white.opacity(0.015))
                            .frame(height: 14)
                    }
                }
                .blur(radius: 0.4)
                .padding(.horizontal, 24)
            }
        }
        .ignoresSafeArea()
    }

    private var springAnimation: Animation {
        .spring(response: 0.42 / motionSpeed.multiplier, dampingFraction: 0.82)
    }

    private func animate(_ updates: () -> Void) {
        withAnimation(springAnimation, updates)
    }

    private func triggerHoverPreview() {
        animate { hoverPreview = true }
        let delay = UInt64((0.9 / motionSpeed.multiplier) * 1_000_000_000)
        Task {
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                withAnimation(springAnimation) {
                    hoverPreview = false
                }
            }
        }
    }

    private func triggerPressPreview() {
        let pressDownDuration = 0.08 / motionSpeed.multiplier
        let releaseDuration = 0.20 / motionSpeed.multiplier

        withAnimation(.easeOut(duration: pressDownDuration)) {
            pressPreview = true
            pressAmount = 1
        }

        let delay = UInt64(pressDownDuration * 1_000_000_000)
        Task {
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                withAnimation(.easeInOut(duration: releaseDuration)) {
                    pressPreview = false
                    pressAmount = 0
                }
            }
        }
    }

    private func finalizeRound(for component: VariantLabComponent) {
        let winner = winnerByComponent[component] ?? .variantA

        for variant in VariantLabMenuVariant.allCases {
            let key = VariantLabDecisionKey(component: component, variant: variant)
            actionsByDecision[key] = (variant == winner) ? .keep : .reject

            if variant != winner && (notesByDecision[key]?.isEmpty ?? true) {
                notesByDecision[key] = "Archived after winner finalized for \(component.rawValue) in round \(roundName)."
            }
            saveDecision(for: variant, in: component)
        }
    }

    private func saveDecision(for variant: VariantLabMenuVariant, in component: VariantLabComponent) {
        let decisionKey = VariantLabDecisionKey(component: component, variant: variant)
        guard let action = actionsByDecision[decisionKey] else { return }

        let ratings = ratingsByDecision[decisionKey] ?? defaultVariantLabRatings()
        let notes = (notesByDecision[decisionKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let record = VariantLabDecisionRecord(
            timestamp: Date(),
            roundName: roundName,
            scenario: scenario,
            component: component,
            variant: variant,
            motionSpeed: motionSpeed,
            action: action,
            ratings: Dictionary(uniqueKeysWithValues: ratings.map { ($0.key.rawValue, $0.value) }),
            notes: notes,
            interaction: VariantLabInteractionSnapshot(
                isExpanded: isExpanded,
                hoverPreview: hoverPreview,
                pressPreview: pressPreview,
                transitionStep: transitionStep
            )
        )

        do {
            latestLogURL = try VariantLabLogStore.shared.appendDecision(record)
            statusMessage = "Saved \(component.rawValue) \(variant.rawValue) as \(action.rawValue) for \(scenario.displayName)."
        } catch {
            statusMessage = "Failed to save decision: \(error.localizedDescription)"
        }
    }

    private func ratingValue(for variant: VariantLabMenuVariant, criterion: VariantLabCriterion) -> Int {
        let key = VariantLabDecisionKey(component: component, variant: variant)
        return ratingsByDecision[key]?[criterion] ?? 3
    }

    private func ratingBinding(for variant: VariantLabMenuVariant, criterion: VariantLabCriterion) -> Binding<Double> {
        Binding(
            get: { Double(ratingValue(for: variant, criterion: criterion)) },
            set: { newValue in
                let key = VariantLabDecisionKey(component: component, variant: variant)
                var variantRatings = ratingsByDecision[key] ?? defaultVariantLabRatings()
                variantRatings[criterion] = Int(newValue.rounded())
                ratingsByDecision[key] = variantRatings
            }
        )
    }

    private func noteBinding(for decisionKey: VariantLabDecisionKey) -> Binding<String> {
        Binding(
            get: { notesByDecision[decisionKey] ?? "" },
            set: { notesByDecision[decisionKey] = $0 }
        )
    }

    private func winnerBinding(for component: VariantLabComponent) -> Binding<VariantLabMenuVariant> {
        Binding(
            get: { winnerByComponent[component] ?? .variantA },
            set: { winnerByComponent[component] = $0 }
        )
    }

    private func actionColor(_ action: VariantLabDecisionAction) -> Color {
        switch action {
        case .keep: return FFColor.success
        case .reject: return FFColor.danger
        case .needsTweak: return FFColor.warning
        }
    }
}

private struct VariantPreviewCard: View {
    let variant: VariantLabMenuVariant
    let component: VariantLabComponent
    let scenario: VariantLabScenario
    let snapshot: VariantLabScenarioSnapshot
    let isExpanded: Bool
    let hoverPreview: Bool
    let pressAmount: CGFloat
    let transitionStep: Int
    let animation: Animation
    let materialProfile: StudioMaterialProfile
    let materialOpacity: Double
    let highlightStrength: Double
    let motionIntensity: Double
    let ringScaleTuning: Double
    let ringStrokeTuning: Double
    let ringTextTuning: Double
    let buttonProminence: Double
    let buttonSecondaryOpacity: Double
    let buttonSpacingTuning: Double
    let glassEdgeStrength: Double
    let glassBloomStrength: Double
    let motionHoverTuning: Double
    let motionPressTuning: Double
    let motionDriftTuning: Double
    let backdropStyle: VariantBackdropStyle

    var body: some View {
        Group {
            switch component {
            case .timerRing:
                timerRingPreview
            case .buttons:
                buttonsPreview
            case .effects:
                effectsPreview
            case .motion:
                motionPreview
            }
        }
        .padding(FFSpacing.md)
        .background(backgroundForVariant)
        .overlay {
            RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .clipShape(RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous))
        .scaleEffect(hoverPreview ? 1.015 : 1.0)
        .shadow(color: .black.opacity(hoverPreview ? 0.24 : 0.14), radius: hoverPreview ? 24 : 14, y: hoverPreview ? 16 : 8)
        .animation(animation, value: hoverPreview)
    }

    private var backgroundForVariant: some View {
        ZStack {
            backdropScene
            Rectangle().fill(materialFill)
            LinearGradient(colors: backgroundGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if variant == .variantA {
                RadialGradient(
                    colors: [Color.white.opacity(highlightStrength * (0.50 * glassBloomStrength)), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 240
                )
            }

            if variant == .variantB {
                Rectangle()
                    .fill(.white.opacity(0.05))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }

            if variant == .variantC {
                RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08 * glassEdgeStrength), lineWidth: 1.1)
                    .blur(radius: 0.3)
            }
        }
    }

    private var timerRingPreview: some View {
        VStack(spacing: FFSpacing.sm) {
            scenarioBadge
                .frame(maxWidth: .infinity, alignment: .leading)

            ringPreview(scale: ringScale * ringScaleTuning, style: ringStyle)

            Text(snapshot.timerText)
                .font(.system(size: 34 * ringTextTuning, weight: ringWeight, design: .rounded))
                .monospacedDigit()

            Text(snapshot.projectName)
                .font(FFType.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .animation(animation, value: transitionStep)
    }

    private var buttonsPreview: some View {
        VStack(spacing: FFSpacing.sm) {
            HStack {
                Text(snapshot.primaryAction)
                    .font(FFType.meta)
                Spacer()
                Text(snapshot.secondaryAction)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: FFSpacing.xs * buttonSpacingTuning) {
                ForEach(snapshot.chips) { chip in
                    chipView(chip)
                }
            }

            actionRow(isCapsule: variant != .variantB)

            if isExpanded {
                HStack(spacing: FFSpacing.xs * buttonSpacingTuning) {
                    miniIconButton("minus")
                    miniIconButton("plus")
                }
            }
        }
        .animation(animation, value: pressAmount)
        .animation(animation, value: isExpanded)
    }

    private var effectsPreview: some View {
        VStack(spacing: FFSpacing.sm) {
            scenarioBadge
                .frame(maxWidth: .infinity, alignment: .leading)

            RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                .fill(effectFill)
                .overlay {
                    RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                        .strokeBorder(effectStroke, lineWidth: 1.2)
                }
                .frame(height: 196)
                .overlay {
                    VStack(spacing: FFSpacing.xs) {
                        ringPreview(scale: effectRingScale, style: ringStyle)
                        Text(snapshot.footer)
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                    }
                    .padding(FFSpacing.md)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                        .fill(effectGloss)
                }
                .shadow(color: effectShadow, radius: 18, y: 10)

            Text("Material focus: \(variant.title(for: .effects))")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
        }
    }

    private var motionPreview: some View {
        let hoverScale = hoverPreview ? (1 + ((motionHoverScale - 1) * motionIntensity * motionHoverTuning)) : 1.0
        let effectivePressScale = 1 - ((1 - motionPressScale) * motionIntensity * motionPressTuning)
        let baseScale = hoverScale - (hoverScale - effectivePressScale) * pressAmount
        let yOffset: CGFloat = isExpanded ? 0 : motionClosedYOffset
        let pulse = CGFloat((transitionStep % 3) + 1) * 0.01 * motionDriftTuning
        let phase = CGFloat(transitionStep % 4)
        let xOffset = variant == .variantB ? (phase - 1.5) * 4 * motionDriftTuning : 0
        let breathingOpacity = variant == .variantC ? (hoverPreview ? 0.93 : 0.84) : 1.0

        return VStack(spacing: FFSpacing.sm) {
            Text("Tap previews above to inspect motion")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                .fill(motionPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                        .strokeBorder(motionPanelStroke, lineWidth: 1.1)
                }
                .frame(height: 222)
                .overlay {
                    VStack(spacing: FFSpacing.sm) {
                        ringPreview(scale: motionRingScale * baseScale + pulse, style: ringStyle)
                            .opacity(Double(breathingOpacity))
                            .offset(x: xOffset)
                        actionRow(isCapsule: true)
                            .scaleEffect(baseScale)
                            .offset(y: yOffset)
                    }
                    .padding(FFSpacing.md)
                }
                .animation(animation, value: hoverPreview)
                .animation(animation, value: pressAmount)
                .animation(animation, value: isExpanded)
                .animation(animation, value: transitionStep)
                .shadow(color: motionShadow, radius: 14, y: 9)

            Text("Current: hover \(hoverPreview ? "on" : "off"), press \(pressAmount > 0.01 ? "on" : "off"), open \(isExpanded ? "yes" : "no")")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scenarioBadge: some View {
        Text(snapshot.stateLabel)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xxs)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.10))
            }
    }

    private func ringPreview(scale: CGFloat, style: StrokeStyle) -> some View {
        TimerRingView(
            progress: snapshot.progress,
            timeString: snapshot.timerText,
            label: snapshot.stateLabel,
            state: previewTimerState
        )
        .scaleEffect(scale)
        .frame(width: 200, height: 200)
        .overlay {
            Circle()
                .trim(from: 0, to: max(0.01, snapshot.progress))
                .stroke(Color.white.opacity(0.78), style: style)
                .rotationEffect(.degrees(-90))
                .padding(28)

            if variant == .variantB {
                Circle()
                    .trim(from: 0.62, to: 0.92)
                    .stroke(Color.white.opacity(0.24), style: StrokeStyle(lineWidth: max(1.4, style.lineWidth * 0.42), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(20)
            }

            if variant == .variantC {
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    .padding(22)
            }
        }
    }

    private func actionRow(isCapsule: Bool) -> some View {
        HStack(spacing: FFSpacing.xs * buttonSpacingTuning) {
            Button(snapshot.primaryAction) {}
                .buttonStyle(.glassProminent)
                .buttonBorderShape(isCapsule ? .capsule : .roundedRectangle(radius: FFRadius.control))
                .tint(primaryButtonTint)
                .scaleEffect((buttonProminence) - (0.04 * pressAmount))
                .animation(animation, value: pressAmount)

            Button(snapshot.secondaryAction) {}
                .buttonStyle(.glassProminent)
                .buttonBorderShape(isCapsule ? .capsule : .roundedRectangle(radius: FFRadius.control))
                .tint(.white.opacity(buttonSecondaryOpacity))
        }
    }

    private var backgroundMaterialOpacity: Double {
        switch variant {
        case .variantA: return 0.90
        case .variantB: return 0.94
        case .variantC: return 0.98
        }
    }

    private var materialFill: AnyShapeStyle {
        let opacity = backgroundMaterialOpacity * materialOpacity
        switch materialProfile {
        case .crystal:
            return AnyShapeStyle(.ultraThinMaterial.opacity(opacity))
        case .balanced:
            return AnyShapeStyle(.thinMaterial.opacity(opacity))
        case .frosted:
            return AnyShapeStyle(.regularMaterial.opacity(opacity))
        }
    }

    private var backgroundGradientColors: [Color] {
        switch variant {
        case .variantA:
            return [Color.white.opacity(highlightStrength * 0.75), Color.white.opacity(0.03), Color.black.opacity(0.05)]
        case .variantB:
            return [Color.white.opacity(highlightStrength * 0.45), Color.white.opacity(0.02), Color.black.opacity(0.05)]
        case .variantC:
            return [Color.white.opacity(highlightStrength * 0.3), Color.white.opacity(0.01), Color.black.opacity(0.04)]
        }
    }

    private var backdropScene: some View {
        ZStack {
            switch backdropStyle {
            case .studio:
                LinearGradient(
                    colors: [Color.black.opacity(0.24), Color.white.opacity(0.02), Color.black.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

            case .aurora:
                LinearGradient(
                    colors: [Color.black.opacity(0.20), Color.blue.opacity(0.10), Color.cyan.opacity(0.08), Color.black.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    RadialGradient(
                        colors: [Color.white.opacity(0.14), .clear],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 180
                    )
                }

            case .contrast:
                VStack(spacing: 10) {
                    ForEach(0..<10, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.07) : Color.white.opacity(0.015))
                            .frame(height: 8)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func chipView(_ chip: VariantLabChip) -> some View {
        Text(chip.title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xxs)
            .background(chip.tone, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08))
            }
    }

    private func miniIconButton(_ icon: String) -> some View {
        Button {} label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(.white.opacity(0.45))
    }

    private var ringScale: CGFloat {
        switch variant {
        case .variantA: return 0.78
        case .variantB: return 0.68
        case .variantC: return 0.72
        }
    }

    private var ringWeight: Font.Weight {
        switch variant {
        case .variantA: return .semibold
        case .variantB: return .medium
        case .variantC: return .light
        }
    }

    private var ringStyle: StrokeStyle {
        let tuning = ringStrokeTuning
        switch variant {
        case .variantA:
            return StrokeStyle(lineWidth: 6 * tuning, lineCap: .round)
        case .variantB:
            return StrokeStyle(lineWidth: 4.5 * tuning, lineCap: .round)
        case .variantC:
            return StrokeStyle(lineWidth: 3.5 * tuning, lineCap: .round)
        }
    }

    private var primaryButtonTint: Color {
        let prominenceOpacity = min(0.95, max(0.30, 0.42 + (buttonProminence * 0.24)))
        switch variant {
        case .variantA: return .white.opacity(min(1.0, prominenceOpacity + 0.10))
        case .variantB: return .white.opacity(min(1.0, prominenceOpacity + 0.04))
        case .variantC: return .white.opacity(prominenceOpacity)
        }
    }

    private var effectFill: AnyShapeStyle {
        switch variant {
        case .variantA:
            return AnyShapeStyle(.regularMaterial.opacity(0.93))
        case .variantB:
            return AnyShapeStyle(.thickMaterial.opacity(0.86))
        case .variantC:
            return AnyShapeStyle(.ultraThinMaterial.opacity(0.99))
        }
    }

    private var effectStroke: Color {
        switch variant {
        case .variantA: return .white.opacity(0.22 * glassEdgeStrength)
        case .variantB: return .white.opacity(0.14 * glassEdgeStrength)
        case .variantC: return .white.opacity(0.18 * glassEdgeStrength)
        }
    }

    private var effectShadow: Color {
        switch variant {
        case .variantA: return .black.opacity(0.26)
        case .variantB: return .black.opacity(0.17)
        case .variantC: return .black.opacity(0.12)
        }
    }

    private var effectRingScale: CGFloat {
        switch variant {
        case .variantA: return 0.47
        case .variantB: return 0.42
        case .variantC: return 0.39
        }
    }

    private var effectGloss: AnyShapeStyle {
        switch variant {
        case .variantA:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.white.opacity(0.12 * glassBloomStrength), .clear, .white.opacity(0.03 * glassBloomStrength)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .variantB:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.white.opacity(0.06 * glassBloomStrength), .clear, .white.opacity(0.01 * glassBloomStrength)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .variantC:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.white.opacity(0.10 * glassBloomStrength), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var motionRingScale: CGFloat {
        switch variant {
        case .variantA: return 0.70
        case .variantB: return 0.63
        case .variantC: return 0.66
        }
    }

    private var motionHoverScale: CGFloat {
        switch variant {
        case .variantA: return 1.06
        case .variantB: return 1.03
        case .variantC: return 1.015
        }
    }

    private var motionPressScale: CGFloat {
        switch variant {
        case .variantA: return 0.94
        case .variantB: return 0.96
        case .variantC: return 0.98
        }
    }

    private var motionClosedYOffset: CGFloat {
        switch variant {
        case .variantA: return 16
        case .variantB: return 10
        case .variantC: return 8
        }
    }

    private var motionPanelFill: AnyShapeStyle {
        switch variant {
        case .variantA:
            return AnyShapeStyle(.regularMaterial.opacity(0.88))
        case .variantB:
            return AnyShapeStyle(.thickMaterial.opacity(0.78))
        case .variantC:
            return AnyShapeStyle(.ultraThinMaterial.opacity(0.96))
        }
    }

    private var motionPanelStroke: Color {
        switch variant {
        case .variantA: return .white.opacity(0.20)
        case .variantB: return .white.opacity(0.13)
        case .variantC: return .white.opacity(0.11)
        }
    }

    private var motionShadow: Color {
        switch variant {
        case .variantA: return .black.opacity(0.24)
        case .variantB: return .black.opacity(0.16)
        case .variantC: return .black.opacity(0.12)
        }
    }

    private var previewTimerState: TimerState {
        switch scenario {
        case .idle, .sessionComplete:
            return .idle
        case .running, .overtime:
            return .focusing
        case .paused:
            return .paused
        }
    }
}
