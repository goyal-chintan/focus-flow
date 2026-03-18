import SwiftUI

struct DesignLabWorkbenchView: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var tokenStore

    @State private var decisionStore = DesignLabDecisionStore()
    @State private var selectedComponent: DesignLabComponent = .material
    @State private var selectedScenario: VariantLabScenario = .idle
    @State private var motionSpeed: VariantLabMotionSpeed = .x1
    @State private var isExpanded = true
    @State private var hoverPreview = false
    @State private var pressPreview = false
    @State private var pressAmount: CGFloat = 0
    @State private var transitionStep = 0
    @State private var selectedSurface: DesignLabSurfaceTarget = .menuBar
    @State private var feedbackMessage = "Pick a component, compare A/B/C, and then lock only the winner."

    var body: some View {
        @Bindable var decisionStore = decisionStore

        ScrollView {
            VStack(alignment: .leading, spacing: FFSpacing.lg) {
                heroSection(decisionStore: decisionStore)
                componentOverviewSection(decisionStore: decisionStore)
                usageSection
                interactionControlsSection()
                variantComparisonSection(decisionStore: decisionStore)
                tuningSection(decisionStore: decisionStore)
                decisionSection(decisionStore: decisionStore)
                confirmationSection()
            }
            .padding(FFSpacing.lg)
        }
        .background(backgroundLayer)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.18),
                Color.white.opacity(0.02),
                Color.black.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [FFColor.focus.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 540
            )
            .blendMode(.screen)
        }
    }

    private func heroSection(decisionStore: DesignLabDecisionStore) -> some View {
        PremiumSurface(style: .hero) {
            HStack(alignment: .top, spacing: FFSpacing.lg) {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("FocusFlow 2 · Design Lab")
                        .font(FFType.titleLarge)

                    Text("Component-first review for liquid-glass material, motion, timer ring, and primary buttons.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: FFSpacing.xs) {
                        statusChip(selectedComponent.icon, title: selectedComponent.rawValue, tint: selectedComponent.tint)
                        statusChip(decisionStore.decision(for: selectedComponent).phase.icon, title: decisionStore.decision(for: selectedComponent).phase.title, tint: decisionStore.decision(for: selectedComponent).phase.tint)
                        statusChip("scope", title: selectedSurface.rawValue, tint: FFColor.success)
                    }
                }

                Spacer(minLength: FFSpacing.md)

                VStack(alignment: .trailing, spacing: FFSpacing.xs) {
                    Text("What this lab does")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                    Text("1. Compare A/B/C")
                        .font(FFType.callout)
                    Text("2. Tune only the winning direction")
                        .font(FFType.callout)
                    Text("3. Lock it and promote a snapshot")
                        .font(FFType.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 320, alignment: .trailing)
            }

            if !feedbackMessage.isEmpty {
                HStack(spacing: FFSpacing.xs) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(FFColor.focus)
                    Text(feedbackMessage)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.top, FFSpacing.xs)
            }
        }
    }

    private func componentOverviewSection(decisionStore: DesignLabDecisionStore) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("Component Bench")
                .font(FFType.title)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 220), spacing: FFSpacing.md),
                    GridItem(.flexible(minimum: 220), spacing: FFSpacing.md),
                    GridItem(.flexible(minimum: 220), spacing: FFSpacing.md),
                    GridItem(.flexible(minimum: 220), spacing: FFSpacing.md)
                ],
                spacing: FFSpacing.md
            ) {
                ForEach(DesignLabComponent.allCases) { component in
                    Button {
                        selectedComponent = component
                        feedbackMessage = "Focused \(component.rawValue). Review its A/B/C cards and tune only that component."
                    } label: {
                        DesignLabOverviewCard(
                            component: component,
                            decision: decisionStore.decision(for: component),
                            isSelected: component == selectedComponent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var usageSection: some View {
        PremiumSurface(style: .card) {
            HStack(alignment: .top, spacing: FFSpacing.lg) {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("How to use this layout")
                        .font(FFType.title)

                    Text("1. Pick one component from the bench.")
                        .font(FFType.meta)
                    Text("2. Compare the three variants and write variant notes.")
                        .font(FFType.meta)
                    Text("3. Use the guided fixes if a slider is obviously off.")
                        .font(FFType.meta)
                    Text("4. Lock one winner, then promote a snapshot.")
                        .font(FFType.meta)
                }

                Spacer(minLength: FFSpacing.lg)

                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("What to check")
                        .font(FFType.title)
                    ForEach(selectedComponent.checklistItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: FFSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(selectedComponent.tint)
                            Text(item)
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
        }
    }

    private func interactionControlsSection() -> some View {
        PremiumSurface(style: .card) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text("Interaction Preview")
                            .font(FFType.title)
                        Text(selectedComponent.reviewPrompt)
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("State: \(selectedScenario.displayName)")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: FFSpacing.md) {
                    controlGroup(title: "Scenario") {
                        Picker("Scenario", selection: $selectedScenario) {
                            ForEach(VariantLabScenario.allCases) { scenario in
                                Text(scenario.displayName).tag(scenario)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    controlGroup(title: "Motion Speed") {
                        Picker("Motion Speed", selection: $motionSpeed) {
                            ForEach(VariantLabMotionSpeed.allCases) { speed in
                                Text(speed.rawValue).tag(speed)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                HStack(spacing: FFSpacing.sm) {
                    Button(isExpanded ? "Close Preview" : "Open Preview") {
                        withAnimation(springAnimation) {
                            isExpanded.toggle()
                        }
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
                        withAnimation(springAnimation) {
                            transitionStep += 1
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.55))

                    Spacer()
                }
            }
        }
    }

    private func variantComparisonSection(decisionStore: DesignLabDecisionStore) -> some View {
        let snapshot = selectedScenario.snapshot(transitionStep: transitionStep)

        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("A/B/C Preview")
                        .font(FFType.title)
                    Text("Each card is a real preview of the selected component, not a tiny visual tweak.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Current: \(selectedComponent.rawValue)")
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 320), spacing: FFSpacing.md),
                    GridItem(.flexible(minimum: 320), spacing: FFSpacing.md),
                    GridItem(.flexible(minimum: 320), spacing: FFSpacing.md)
                ],
                spacing: FFSpacing.md
            ) {
                ForEach(DesignLabVariant.allCases) { variant in
                    DesignLabVariantPreviewCard(
                        component: selectedComponent,
                        variant: variant,
                        selectedScenario: selectedScenario,
                        scenario: snapshot,
                        isExpanded: isExpanded,
                        hoverPreview: hoverPreview,
                        pressPreview: pressPreview,
                        pressAmount: pressAmount,
                        transitionStep: transitionStep,
                        motionSpeed: motionSpeed,
                        tokens: tokens,
                        decisionStore: decisionStore,
                        onKeep: {
                            decisionStore.setWinner(variant, for: selectedComponent)
                            decisionStore.setVariantVerdict(.keep, for: selectedComponent, variant: variant)
                            decisionStore.markCompared(for: selectedComponent)
                            feedbackMessage = "Kept \(variant.rawValue) for \(selectedComponent.rawValue)."
                        },
                        onReject: {
                            decisionStore.setVariantVerdict(.reject, for: selectedComponent, variant: variant)
                            decisionStore.markCompared(for: selectedComponent)
                            feedbackMessage = "Rejected \(variant.rawValue) for \(selectedComponent.rawValue)."
                        },
                        onNeedsTweak: {
                            decisionStore.setVariantVerdict(.needsTweak, for: selectedComponent, variant: variant)
                            decisionStore.markTuned(for: selectedComponent)
                            feedbackMessage = "\(variant.rawValue) needs another pass for \(selectedComponent.rawValue)."
                        }
                    )
                }
            }
        }
    }

    private func tuningSection(decisionStore: DesignLabDecisionStore) -> some View {
        PremiumSurface(style: .card) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text("\(selectedComponent.rawValue) Tuning")
                            .font(FFType.title)
                        Text("Use sliders only for the active component. Keep the rest of the system stable.")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset Section") {
                        resetCurrentComponent()
                        decisionStore.reset(selectedComponent)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.5))
                }

                switch selectedComponent {
                case .material:
                    materialTuningSection(decisionStore: decisionStore)
                case .motion:
                    motionTuningSection(decisionStore: decisionStore)
                case .timerRing:
                    ringTuningSection(decisionStore: decisionStore)
                case .primaryButtons:
                    buttonTuningSection(decisionStore: decisionStore)
                }
            }
        }
    }

    private func decisionSection(decisionStore: DesignLabDecisionStore) -> some View {
        let decision = decisionStore.decision(for: selectedComponent)

        return PremiumSurface(style: .card) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text("Decision Card")
                            .font(FFType.title)
                        Text("Winner, notes, lock status, and promote gate for \(selectedComponent.rawValue).")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusChip(decision.phase.icon, title: decision.phase.title, tint: decision.phase.tint)
                }

                HStack(spacing: FFSpacing.xs) {
                    ForEach(DesignLabVariant.allCases) { variant in
                        let verdict = decisionStore.variantDecision(for: selectedComponent, variant: variant).verdict
                        HStack(spacing: FFSpacing.xxs) {
                            Circle()
                                .fill(verdict.tint)
                                .frame(width: 8, height: 8)
                            Text("\(variant.rawValue): \(verdict.rawValue)")
                                .font(FFType.meta)
                        }
                        .padding(.horizontal, FFSpacing.sm)
                        .padding(.vertical, FFSpacing.xxs)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }

                Picker("Winner", selection: decisionStore.winnerBinding(for: selectedComponent)) {
                    ForEach(DesignLabVariant.allCases) { variant in
                        Text(variant.rawValue).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color.white.opacity(0.72))

                TextField("Why is this the right direction?", text: decisionStore.notesBinding(for: selectedComponent), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)

                HStack(spacing: FFSpacing.sm) {
                    Button("Mark Compared") {
                        decisionStore.markCompared(for: selectedComponent)
                        feedbackMessage = "\(selectedComponent.rawValue) marked compared."
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white.opacity(0.45))

                    Button("Lock Winner") {
                        if decisionStore.lock(selectedComponent) {
                            feedbackMessage = "\(selectedComponent.rawValue) locked."
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FFColor.success)

                    Button("Promote Snapshot") {
                        promoteCurrentComponent(decisionStore: decisionStore)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FFColor.deepFocus)

                    Spacer()
                }

                HStack(spacing: FFSpacing.sm) {
                    Text(decisionStore.summary(for: selectedComponent))
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(decisionStore.isLocked(for: selectedComponent) ? "Locked" : "Unlocked")
                        .font(FFType.meta)
                        .foregroundStyle(decisionStore.isLocked(for: selectedComponent) ? FFColor.success : .secondary)
                    Text(decisionStore.isPromoted(for: selectedComponent) ? "Promoted" : "Not promoted")
                        .font(FFType.meta)
                        .foregroundStyle(decisionStore.isPromoted(for: selectedComponent) ? FFColor.deepFocus : .secondary)
                }
            }
        }
    }

    private func confirmationSection() -> some View {
        PremiumSurface(style: .card) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text("Surface Confirmation")
                            .font(FFType.title)
                        Text("Check the locked winner in the three places it must still feel coherent.")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Surface", selection: $selectedSurface) {
                        ForEach(DesignLabSurfaceTarget.allCases) { surface in
                            Text(surface.rawValue).tag(surface)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.white.opacity(0.72))
                    .frame(width: 460)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 240), spacing: FFSpacing.md),
                        GridItem(.flexible(minimum: 240), spacing: FFSpacing.md),
                        GridItem(.flexible(minimum: 240), spacing: FFSpacing.md)
                    ],
                    spacing: FFSpacing.md
                ) {
                    ForEach(DesignLabSurfaceTarget.allCases) { surface in
                        DesignLabSurfacePreviewCard(
                            surface: surface,
                            component: selectedComponent,
                            selectedSurface: selectedSurface,
                            snapshot: selectedScenario.snapshot(transitionStep: transitionStep),
                            winner: decisionStore.decision(for: selectedComponent).winner,
                            tokens: tokens
                        )
                    }
                }
            }
        }
    }

    private func controlGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text(title)
                .font(FFType.meta)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusChip(_ icon: String, title: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(FFType.meta)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xxs)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.18))
            }
    }

    private var springAnimation: Animation {
        .spring(response: 0.42 / motionSpeed.multiplier, dampingFraction: 0.82)
    }

    private func triggerHoverPreview() {
        withAnimation(springAnimation) {
            hoverPreview = true
        }

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

    private func promoteCurrentComponent(decisionStore: DesignLabDecisionStore) {
        guard decisionStore.promote(selectedComponent) else {
            feedbackMessage = "Lock \(selectedComponent.rawValue) before promoting."
            return
        }

        let decision = decisionStore.decision(for: selectedComponent)
        let variantName = "\(selectedComponent.rawValue) · \(decision.winner.shortName) Snapshot"
        let description = decisionStore.summary(for: selectedComponent)
        tokenStore.save(
            FFDesignVariant(
                name: variantName,
                description: description,
                tokens: tokens.copy()
            )
        )
        feedbackMessage = "Promoted \(variantName) and saved a snapshot."
    }

    private func resetCurrentComponent() {
        let defaults = FFDesignTokens()
        tokenStore.pushUndo(tokens)

        switch selectedComponent {
        case .material:
            tokens.color.panelFillOpacity = defaults.color.panelFillOpacity
            tokens.color.panelBorderOpacity = defaults.color.panelBorderOpacity
            tokens.color.panelHighlightOpacity = defaults.color.panelHighlightOpacity
            tokens.color.insetFillOpacity = defaults.color.insetFillOpacity
            tokens.color.rowFillOpacity = defaults.color.rowFillOpacity
            tokens.color.fieldFillOpacity = defaults.color.fieldFillOpacity
            tokens.color.fieldBorderOpacity = defaults.color.fieldBorderOpacity
        case .motion:
            tokens.motion = FFMotionTokens()
        case .timerRing:
            tokens.ring = FFRingTokens()
        case .primaryButtons:
            tokens.radius.control = defaults.radius.control
            tokens.radius.card = defaults.radius.card
            tokens.sizing.controlMin = defaults.sizing.controlMin
            tokens.sizing.iconFrame = defaults.sizing.iconFrame
            tokens.spacing.sm = defaults.spacing.sm
            tokens.spacing.md = defaults.spacing.md
            tokens.typography.calloutSize = defaults.typography.calloutSize
            tokens.typography.calloutWeight = defaults.typography.calloutWeight
            tokens.typography.metaSize = defaults.typography.metaSize
            tokens.typography.metaWeight = defaults.typography.metaWeight
        }
    }

    private func materialTuningSection(decisionStore: DesignLabDecisionStore) -> some View {
        @Bindable var tokens = tokens
        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("Material properties")
                .font(FFType.meta)
                .foregroundStyle(.secondary)

            DesignLabSliderRow(label: "panelFillOpacity", value: $tokens.color.panelFillOpacity, defaultValue: FFColorTokens().panelFillOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "panelBorderOpacity", value: $tokens.color.panelBorderOpacity, defaultValue: FFColorTokens().panelBorderOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "panelHighlightOpacity", value: $tokens.color.panelHighlightOpacity, defaultValue: FFColorTokens().panelHighlightOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "insetFillOpacity", value: $tokens.color.insetFillOpacity, defaultValue: FFColorTokens().insetFillOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "rowFillOpacity", value: $tokens.color.rowFillOpacity, defaultValue: FFColorTokens().rowFillOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }

            recommendationRow(actions: materialSuggestions(decisionStore: decisionStore))
        }
    }

    private func motionTuningSection(decisionStore: DesignLabDecisionStore) -> some View {
        @Bindable var tokens = tokens
        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("Motion properties")
                .font(FFType.meta)
                .foregroundStyle(.secondary)

            DesignLabSliderRow(label: "popoverResponse", value: $tokens.motion.popoverResponse, defaultValue: FFMotionTokens().popoverResponse, range: 0.05...3.0, step: 0.02) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "popoverDamping", value: $tokens.motion.popoverDamping, defaultValue: FFMotionTokens().popoverDamping, range: 0.1...1.5, step: 0.02) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "sectionResponse", value: $tokens.motion.sectionResponse, defaultValue: FFMotionTokens().sectionResponse, range: 0.05...3.0, step: 0.02) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "sectionDamping", value: $tokens.motion.sectionDamping, defaultValue: FFMotionTokens().sectionDamping, range: 0.1...1.5, step: 0.02) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "controlResponse", value: $tokens.motion.controlResponse, defaultValue: FFMotionTokens().controlResponse, range: 0.05...3.0, step: 0.02) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "controlDamping", value: $tokens.motion.controlDamping, defaultValue: FFMotionTokens().controlDamping, range: 0.1...1.5, step: 0.02) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "breathingDuration", value: $tokens.motion.breathingDuration, defaultValue: FFMotionTokens().breathingDuration, range: 0.5...5.0, step: 0.1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }

            recommendationRow(actions: motionSuggestions(decisionStore: decisionStore))
        }
    }

    private func ringTuningSection(decisionStore: DesignLabDecisionStore) -> some View {
        @Bindable var tokens = tokens
        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("Ring properties")
                .font(FFType.meta)
                .foregroundStyle(.secondary)

            DesignLabSliderRow(label: "size", value: $tokens.ring.size, defaultValue: FFRingTokens().size, range: 80...400, step: 1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "strokeWidth", value: $tokens.ring.strokeWidth, defaultValue: FFRingTokens().strokeWidth, range: 1...20, step: 0.1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "timerFontSize", value: $tokens.ring.timerFontSize, defaultValue: FFRingTokens().timerFontSize, range: 20...120, step: 0.5) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            TokenPicker(label: "timerFontWeight", selection: $tokens.ring.timerFontWeight)
            DesignLabSliderRow(label: "labelFontSize", value: $tokens.ring.labelFontSize, defaultValue: FFRingTokens().labelFontSize, range: 8...30, step: 0.5) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            TokenPicker(label: "labelFontWeight", selection: $tokens.ring.labelFontWeight)
            DesignLabSliderRow(label: "digitTracking", value: $tokens.ring.digitTracking, defaultValue: FFRingTokens().digitTracking, range: 0...10, step: 0.1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "labelTracking", value: $tokens.ring.labelTracking, defaultValue: FFRingTokens().labelTracking, range: 0...10, step: 0.1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "backgroundDiscOpacity", value: $tokens.ring.backgroundDiscOpacity, defaultValue: FFRingTokens().backgroundDiscOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "trackOpacity", value: $tokens.ring.trackOpacity, defaultValue: FFRingTokens().trackOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "glowRadius", value: $tokens.ring.glowRadius, defaultValue: FFRingTokens().glowRadius, range: 0...30, step: 0.5) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "glowOpacity", value: $tokens.ring.glowOpacity, defaultValue: FFRingTokens().glowOpacity, range: 0...1, step: 0.01) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }

            recommendationRow(actions: ringSuggestions(decisionStore: decisionStore))
        }
    }

    private func buttonTuningSection(decisionStore: DesignLabDecisionStore) -> some View {
        @Bindable var tokens = tokens
        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("Button properties")
                .font(FFType.meta)
                .foregroundStyle(.secondary)

            DesignLabSliderRow(label: "controlMin", value: $tokens.sizing.controlMin, defaultValue: FFSizeTokens().controlMin, range: 28...64, step: 1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "iconFrame", value: $tokens.sizing.iconFrame, defaultValue: FFSizeTokens().iconFrame, range: 28...64, step: 1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "controlRadius", value: $tokens.radius.control, defaultValue: FFRadiusTokens().control, range: 8...24, step: 0.5) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "cardRadius", value: $tokens.radius.card, defaultValue: FFRadiusTokens().card, range: 12...28, step: 0.5) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "spacing.sm", value: $tokens.spacing.sm, defaultValue: FFSpacingTokens().sm, range: 8...24, step: 1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "spacing.md", value: $tokens.spacing.md, defaultValue: FFSpacingTokens().md, range: 10...28, step: 1) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            DesignLabSliderRow(label: "calloutSize", value: $tokens.typography.calloutSize, defaultValue: FFTypographyTokens().calloutSize, range: 10...22, step: 0.5) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            TokenPicker(label: "calloutWeight", selection: $tokens.typography.calloutWeight)
            DesignLabSliderRow(label: "metaSize", value: $tokens.typography.metaSize, defaultValue: FFTypographyTokens().metaSize, range: 10...20, step: 0.5) {
                tokenStore.pushUndo(tokens)
                decisionStore.markTuned(for: selectedComponent)
            }
            TokenPicker(label: "metaWeight", selection: $tokens.typography.metaWeight)

            recommendationRow(actions: buttonSuggestions(decisionStore: decisionStore))
        }
    }

    private func recommendationRow(actions: [DesignLabGuidedFixAction]) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text("Guided fixes")
                .font(FFType.meta)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: FFSpacing.sm) {
                ForEach(actions) { action in
                    Button {
                        tokenStore.pushUndo(tokens)
                        action.apply()
                        decisionStore.appendSuggestion(action.suggestion, for: selectedComponent)
                        decisionStore.markTuned(for: selectedComponent)
                        feedbackMessage = action.suggestion.explanation
                    } label: {
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(action.suggestion.title)
                                .font(FFType.callout)
                                .foregroundStyle(.primary)
                            Text(action.suggestion.adjustmentSummary)
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(action.suggestion.confidence)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(FFColor.focus)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(FFSpacing.sm)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: FFRadius.control))
                }
            }
        }
    }

    private func materialSuggestions(decisionStore: DesignLabDecisionStore) -> [DesignLabGuidedFixAction] {
        [
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .material,
                    title: "More glass",
                    explanation: "Reduce tint and highlight so the surface feels like liquid glass, not a flat gray plate.",
                    adjustmentSummary: "Lower fill opacity and highlight; keep the border thin.",
                    confidence: "High confidence"
                ),
                apply: {
                    tokens.color.panelFillOpacity = max(0.02, tokens.color.panelFillOpacity - 0.015)
                    tokens.color.panelHighlightOpacity = max(0.04, tokens.color.panelHighlightOpacity - 0.02)
                    tokens.color.panelBorderOpacity = min(0.14, tokens.color.panelBorderOpacity + 0.01)
                }
            ),
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .material,
                    title: "Calmer depth",
                    explanation: "Keep the material readable, but reduce the visual edge and inset noise.",
                    adjustmentSummary: "Lower inset and row fill slightly.",
                    confidence: "Medium confidence"
                ),
                apply: {
                    tokens.color.insetFillOpacity = max(0.03, tokens.color.insetFillOpacity - 0.01)
                    tokens.color.rowFillOpacity = max(0.02, tokens.color.rowFillOpacity - 0.01)
                }
            )
        ]
    }

    private func motionSuggestions(decisionStore: DesignLabDecisionStore) -> [DesignLabGuidedFixAction] {
        [
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .motion,
                    title: "Smoother settle",
                    explanation: "The press should release cleanly without a snap or jitter.",
                    adjustmentSummary: "Raise damping and shorten the response slightly.",
                    confidence: "High confidence"
                ),
                apply: {
                    tokens.motion.popoverDamping = min(1.05, tokens.motion.popoverDamping + 0.06)
                    tokens.motion.sectionDamping = min(1.05, tokens.motion.sectionDamping + 0.05)
                    tokens.motion.controlDamping = min(1.0, tokens.motion.controlDamping + 0.05)
                    tokens.motion.controlResponse = max(0.08, tokens.motion.controlResponse - 0.03)
                }
            ),
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .motion,
                    title: "Less twitch",
                    explanation: "Reduce motion intensity so the lab feels deliberate and premium.",
                    adjustmentSummary: "Slow section movement and lengthen breathing a touch.",
                    confidence: "Medium confidence"
                ),
                apply: {
                    tokens.motion.sectionResponse = min(0.45, tokens.motion.sectionResponse + 0.03)
                    tokens.motion.breathingDuration = min(2.6, tokens.motion.breathingDuration + 0.2)
                }
            )
        ]
    }

    private func ringSuggestions(decisionStore: DesignLabDecisionStore) -> [DesignLabGuidedFixAction] {
        [
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .timerRing,
                    title: "Make the number more dominant",
                    explanation: "The countdown number should stay readable at a distance before the ring itself.",
                    adjustmentSummary: "Increase timer size and tighten tracking a little.",
                    confidence: "High confidence"
                ),
                apply: {
                    tokens.ring.timerFontSize = min(76, tokens.ring.timerFontSize + 4)
                    tokens.ring.digitTracking = max(0.2, tokens.ring.digitTracking - 0.2)
                    tokens.ring.labelFontSize = min(20, tokens.ring.labelFontSize + 1)
                }
            ),
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .timerRing,
                    title: "Calm the ring",
                    explanation: "The ring should read as a stable material layer, not a neon effect.",
                    adjustmentSummary: "Reduce glow and tighten the stroke a touch.",
                    confidence: "Medium confidence"
                ),
                apply: {
                    tokens.ring.glowOpacity = max(0.18, tokens.ring.glowOpacity - 0.08)
                    tokens.ring.glowRadius = max(4, tokens.ring.glowRadius - 2)
                    tokens.ring.strokeWidth = max(2.5, tokens.ring.strokeWidth - 0.4)
                }
            )
        ]
    }

    private func buttonSuggestions(decisionStore: DesignLabDecisionStore) -> [DesignLabGuidedFixAction] {
        [
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .primaryButtons,
                    title: "More prominence",
                    explanation: "The primary CTA should feel obvious but still glassy.",
                    adjustmentSummary: "Increase control size and give the buttons a little more air.",
                    confidence: "High confidence"
                ),
                apply: {
                    tokens.sizing.controlMin = min(52, tokens.sizing.controlMin + 4)
                    tokens.radius.control = min(16, tokens.radius.control + 1)
                    tokens.spacing.md = min(24, tokens.spacing.md + 2)
                }
            ),
            DesignLabGuidedFixAction(
                suggestion: DesignLabGuidedFixSuggestion(
                    component: .primaryButtons,
                    title: "Quiet the rail",
                    explanation: "Pull the secondary controls back so the interface stays calm.",
                    adjustmentSummary: "Lower the text size slightly and tighten the chrome.",
                    confidence: "Medium confidence"
                ),
                apply: {
                    tokens.typography.calloutSize = max(11, tokens.typography.calloutSize - 0.5)
                    tokens.typography.metaSize = max(10, tokens.typography.metaSize - 0.5)
                    tokens.radius.card = max(16, tokens.radius.card - 1)
                }
            )
        ]
    }
}

private struct DesignLabGuidedFixAction: Identifiable {
    let id = UUID()
    let suggestion: DesignLabGuidedFixSuggestion
    let apply: () -> Void
}

private struct DesignLabOverviewCard: View {
    let component: DesignLabComponent
    let decision: DesignLabComponentDecision
    let isSelected: Bool

    var body: some View {
        PremiumSurface(style: .inset) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                HStack(alignment: .top) {
                    Label(component.rawValue, systemImage: component.icon)
                        .font(FFType.callout)
                    Spacer()
                    statusChip(decision.phase.icon, tint: decision.phase.tint)
                }

                Text(component.subtitle)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Winner: \(decision.winner.shortName) · \(decision.phase.title)")
                    .font(FFType.meta)
                    .foregroundStyle(isSelected ? component.tint : .secondary)

                Text(component.rawValue == "Material" ? "Focus on glass first." : component.rawValue == "Motion" ? "Focus on interaction rhythm." : component.rawValue == "Timer Ring" ? "Focus on number-first hierarchy." : "Focus on CTA clarity.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                .strokeBorder(isSelected ? component.tint.opacity(0.65) : Color.white.opacity(0.14), lineWidth: isSelected ? 1.4 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 16 : 10, y: isSelected ? 8 : 4)
    }

    private func statusChip(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(6)
            .background(tint.opacity(0.12), in: Circle())
    }
}

private struct DesignLabSliderRow: View {
    let label: String
    @Binding var value: CGFloat
    let defaultValue: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let onEditStart: () -> Void

    var body: some View {
        HStack(spacing: FFSpacing.md) {
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 190, alignment: .leading)

            Slider(value: $value, in: range, step: step) { editing in
                if editing {
                    onEditStart()
                }
            }

            Text(formattedValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)

            Button {
                value = defaultValue
                onEditStart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(value == defaultValue ? 0.3 : 1)
            .disabled(value == defaultValue)
        }
    }

    private var formattedValue: String {
        if step >= 1 {
            String(format: "%.0f", value)
        } else if step >= 0.1 {
            String(format: "%.1f", value)
        } else {
            String(format: "%.2f", value)
        }
    }
}

private struct DesignLabVariantPreviewCard: View {
    let component: DesignLabComponent
    let variant: DesignLabVariant
    let selectedScenario: VariantLabScenario
    let scenario: VariantLabScenarioSnapshot
    let isExpanded: Bool
    let hoverPreview: Bool
    let pressPreview: Bool
    let pressAmount: CGFloat
    let transitionStep: Int
    let motionSpeed: VariantLabMotionSpeed
    let tokens: FFDesignTokens
    let decisionStore: DesignLabDecisionStore
    let onKeep: () -> Void
    let onReject: () -> Void
    let onNeedsTweak: () -> Void

    var body: some View {
        let decision = decisionStore.variantDecision(for: component, variant: variant)
        let isWinner = decisionStore.decision(for: component).winner == variant

        PremiumSurface(style: .card) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text(component.variantTitle(for: variant))
                            .font(FFType.title)
                        Text(component.variantSubtitle(for: variant))
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: FFSpacing.xxs) {
                        statusChip(decision.verdict.rawValue, tint: decision.verdict.tint)
                        if isWinner {
                            statusChip("Winner", tint: component.tint)
                        }
                    }
                }

                previewBody
                    .frame(maxWidth: .infinity)

                HStack(spacing: FFSpacing.xs) {
                    Button("Keep") {
                        onKeep()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(DesignLabVariantVerdict.keep.tint)

                    Button("Reject") {
                        onReject()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(DesignLabVariantVerdict.reject.tint)

                    Button("Needs tweak") {
                        onNeedsTweak()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(DesignLabVariantVerdict.needsTweak.tint)
                }

                TextField("Notes for \(variant.rawValue)", text: decisionStore.variantNotesBinding(for: component, variant: variant), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                .strokeBorder(isWinner ? component.tint.opacity(0.65) : Color.white.opacity(0.14), lineWidth: isWinner ? 1.4 : 1)
        }
        .scaleEffect(hoverPreview ? 1.01 : 1.0)
        .offset(y: pressPreview ? 2 : 0)
        .shadow(color: .black.opacity(hoverPreview ? 0.2 : 0.12), radius: hoverPreview ? 16 : 12, y: hoverPreview ? 10 : 6)
        .animation(springAnimation, value: hoverPreview)
        .animation(springAnimation, value: pressPreview)
    }

    @ViewBuilder
    private var previewBody: some View {
        switch component {
        case .material:
            materialPreview
        case .motion:
            motionPreview
        case .timerRing:
            ringPreview
        case .primaryButtons:
            buttonsPreview
        }
    }

    private var materialPreview: some View {
        let materialStyle: Material = switch variant {
        case .a: .ultraThinMaterial
        case .b: .regularMaterial
        case .c: .thinMaterial
        }

        let cornerRadius: CGFloat = switch variant {
        case .a: 30
        case .b: 24
        case .c: 20
        }

        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(materialStyle)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(materialFillOverlay)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(materialBorder, lineWidth: 1)
                }
                .frame(height: 176)
                .overlay {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        HStack {
                            Text(scenario.stateLabel)
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("A/B/C")
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text("Glass depth")
                                .font(FFType.callout)
                            Text("Border, tint, and highlight should feel native.")
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: FFSpacing.xs) {
                            chip("Opacity")
                            chip("Border")
                            chip("Highlight")
                        }
                    }
                    .padding(FFSpacing.md)
                }

            HStack(spacing: FFSpacing.xs) {
                pill("Fill \(valueText(tokens.color.panelFillOpacity))")
                pill("Border \(valueText(tokens.color.panelBorderOpacity))")
                pill("Glow \(valueText(tokens.color.panelHighlightOpacity))")
            }
        }
    }

    private var motionPreview: some View {
        let travel: CGFloat = switch variant {
        case .a: 24
        case .b: 16
        case .c: 8
        }

        let amplitude = hoverPreview ? travel : travel * 0.45
        let scaleBase: CGFloat = switch variant {
        case .a: 1.06
        case .b: 1.02
        case .c: 1.0
        }

        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14))
                }
                .frame(height: 176)
                .overlay {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        HStack {
                            Text("Hover / press / transition")
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(variant.rawValue)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, FFSpacing.sm)
                                .padding(.vertical, FFSpacing.xxs)
                                .background(FFColor.focus.opacity(0.12), in: Capsule())
                        }

                        Spacer()

                        HStack(spacing: FFSpacing.sm) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(FFColor.focus.opacity(0.18))
                                .frame(width: 72, height: 52)
                                .offset(x: variant == .a ? amplitude : 0, y: variant == .c ? 6 : 0)
                                .scaleEffect(pressPreview ? 0.96 : scaleBase)
                                .animation(springAnimation, value: amplitude)

                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text("Fluid feedback")
                                    .font(FFType.callout)
                                Text("The interaction should settle quickly without wobble.")
                                    .font(FFType.meta)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(FFSpacing.md)
                }

            HStack(spacing: FFSpacing.xs) {
                pill("Response \(valueText(tokens.motion.controlResponse))")
                pill("Damping \(valueText(tokens.motion.controlDamping))")
                pill("Tempo \(valueText(tokens.motion.breathingDuration))")
            }
        }
    }

    private var ringPreview: some View {
        let timerState: TimerState = switch selectedState {
        case .idle: .idle
        case .running: .focusing
        case .paused: .paused
        case .overtime: .onBreak(.longBreak)
        case .sessionComplete: .idle
        }

        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack {
                Text(scenario.projectName)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedStateLabel)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: FFSpacing.md) {
                TimerRingView(
                    progress: scenario.progress,
                    timeString: scenario.timerText,
                    label: ringLabel,
                    state: timerState
                )
                .scaleEffect(variant == .a ? 1.0 : (variant == .b ? 0.88 : 0.82))
                .frame(maxWidth: variant == .a ? 190 : variant == .b ? 160 : 140)

                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text(variant == .a ? "Hero timing" : variant == .b ? "Structured timing" : "Minimal timing")
                        .font(FFType.callout)
                    Text(variant == .a ? "The number should dominate." : variant == .b ? "Balance ring and rail." : "Keep the stage calm.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: FFSpacing.xs) {
                pill("Size \(valueText(tokens.ring.size))")
                pill("Stroke \(valueText(tokens.ring.strokeWidth))")
                pill("Label \(valueText(tokens.ring.labelFontSize))")
            }
        }
    }

    private var buttonsPreview: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack {
                Text(scenario.footer)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(variant == .a ? "Floating CTA" : variant == .b ? "Structured rail" : "Quiet stage")
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                if variant == .a {
                    ControlButton(title: scenario.primaryAction, icon: "play.fill", role: .primary) {}
                    HStack(spacing: FFSpacing.sm) {
                        ControlButton(title: scenario.secondaryAction, icon: "stop.fill", role: .secondary) {}
                        ControlButton(title: "Later", icon: "clock.fill", role: .secondary) {}
                    }
                } else if variant == .b {
                    HStack(spacing: FFSpacing.sm) {
                        ControlButton(title: scenario.primaryAction, icon: "play.fill", role: .primary) {}
                        ControlButton(title: scenario.secondaryAction, icon: "stop.fill", role: .secondary) {}
                    }
                    HStack(spacing: FFSpacing.sm) {
                        ControlButton(title: "Break", icon: "cup.and.saucer.fill", role: .secondary) {}
                        ControlButton(title: "Log", icon: "square.and.pencil", role: .secondary) {}
                    }
                } else {
                    HStack(spacing: FFSpacing.sm) {
                        ControlButton(title: scenario.primaryAction, icon: "play.fill", role: .primary) {}
                        ControlButton(title: scenario.secondaryAction, icon: "stop.fill", role: .secondary) {}
                    }
                }
            }
            .scaleEffect(pressPreview ? 0.98 : 1.0)
            .offset(y: hoverPreview ? -2 : 0)

            HStack(spacing: FFSpacing.xs) {
                pill("Min \(valueText(tokens.sizing.controlMin))")
                pill("Radius \(valueText(tokens.radius.control))")
                pill("Callout \(valueText(tokens.typography.calloutSize))")
            }
        }
    }

    private var selectedState: VariantLabScenario {
        selectedScenario
    }

    private var ringLabel: String {
        switch selectedScenario {
        case .idle: "Ready"
        case .running: "Focusing"
        case .paused: "Paused"
        case .overtime: "Finish strong"
        case .sessionComplete: "Complete"
        }
    }

    private var selectedStateLabel: String {
        selectedScenario.displayName
    }

    private var springAnimation: Animation {
        .spring(response: 0.42 / motionSpeed.multiplier, dampingFraction: 0.82)
    }

    private var materialBorder: Color {
        Color.white.opacity(0.18)
    }

    private var materialFillOverlay: Color {
        switch variant {
        case .a: FFColor.focus.opacity(0.05)
        case .b: Color.white.opacity(0.04)
        case .c: Color.black.opacity(0.04)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xxs)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xxs)
            .background(Color.white.opacity(0.12), in: Capsule())
    }

    private func statusChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xxs)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.18))
            }
    }

    private func valueText<T: BinaryFloatingPoint>(_ value: T) -> String {
        if Double(value).rounded() == Double(value) {
            return String(format: "%.0f", Double(value))
        } else {
            return String(format: "%.1f", Double(value))
        }
    }
}

private struct DesignLabSurfacePreviewCard: View {
    let surface: DesignLabSurfaceTarget
    let component: DesignLabComponent
    let selectedSurface: DesignLabSurfaceTarget
    let snapshot: VariantLabScenarioSnapshot
    let winner: DesignLabVariant
    let tokens: FFDesignTokens

    var body: some View {
        PremiumSurface(style: .inset) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Label(surface.rawValue, systemImage: surface.icon)
                        .font(FFType.callout)
                    Spacer()
                    if surface == selectedSurface {
                        Text("Focused")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, FFSpacing.sm)
                            .padding(.vertical, FFSpacing.xxs)
                            .background(FFColor.focus.opacity(0.12), in: Capsule())
                    }
                }

                Text(surface.subtitle)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                switch surface {
                case .menuBar:
                    menuBarPreview
                case .sessionComplete:
                    sessionCompletePreview
                case .dashboard:
                    dashboardPreview
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                .strokeBorder(surface == selectedSurface ? FFColor.focus.opacity(0.55) : Color.white.opacity(0.12), lineWidth: surface == selectedSurface ? 1.2 : 1)
        }
    }

    private var menuBarPreview: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text(snapshot.projectName)
                .font(FFType.callout)
            HStack {
                Text("Winner \(winner.rawValue)")
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(component.rawValue)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FFColor.panelFill)
                .frame(height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(FFColor.panelBorder)
                }
        }
    }

    private var sessionCompletePreview: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text("Session Complete")
                .font(FFType.callout)
            Text("Reflect, save, and continue with the same material rhythm.")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ControlButton(title: "Continue", icon: "arrow.right", role: .primary) {}
        }
    }

    private var dashboardPreview: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text("Dashboard")
                .font(FFType.callout)
            HStack {
                Text("Stable hierarchy")
                    .font(FFType.meta)
                Spacer()
                Text(snapshot.footer)
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FFColor.panelFill)
                .frame(height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(FFColor.panelBorder)
                }
        }
    }
}
