import SwiftUI

struct VariantLabLayoutPreviewCard: View {
    let variant: VariantLabLayoutVariant
    let snapshot: VariantLabScenarioSnapshot
    let isExpanded: Bool
    let hoverPreview: Bool
    let pressAmount: CGFloat
    let transitionStep: Int
    let animation: Animation
    let materialProfile: VariantLabMaterialProfile
    let materialOpacity: Double
    let highlightStrength: Double
    let motionIntensity: Double
    let buttonProminence: Double
    let buttonSecondaryOpacity: Double
    let buttonSpacingTuning: Double
    let glassEdgeStrength: Double
    let glassBloomStrength: Double
    let motionHoverTuning: Double
    let motionPressTuning: Double
    let motionDriftTuning: Double
    let backdropStyle: FFLabBackdropStyle

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            header

            canvas
                .animation(animation, value: hoverPreview)
                .animation(animation, value: pressAmount)
                .animation(animation, value: isExpanded)
                .animation(animation, value: transitionStep)

            checklist
        }
        .padding(FFSpacing.md)
        .background(surfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .clipShape(RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous))
        .scaleEffect(hoverPreview ? 1.01 + (0.004 * motionHoverTuning) : 1.0)
        .offset(y: pressAmount > 0.01 ? -2 * motionPressTuning : 0)
        .shadow(color: .black.opacity(hoverPreview ? 0.24 : 0.14), radius: hoverPreview ? 20 : 14, y: hoverPreview ? 14 : 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(variant.layoutTitle)
                    .font(FFType.title)
                Spacer()
                Text(snapshot.stateLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, FFSpacing.sm)
                    .padding(.vertical, FFSpacing.xxs)
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.10))
                    }
            }

            Text(variant.layoutSubtitle)
                .font(FFType.meta)
                .foregroundStyle(.secondary)
        }
    }

    private var canvas: some View {
        ZStack {
            backdropScene
            Rectangle().fill(materialFill)
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if variant == .variantA {
                RadialGradient(
                    colors: [Color.white.opacity(highlightStrength * 0.45), .clear],
                    center: .topLeading,
                    startRadius: 12,
                    endRadius: 220
                )
            }

            if variant == .variantB {
                Rectangle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 1)
                    .padding(.vertical, 18)
                    .offset(x: -68)
            }

            if variant == .variantC {
                RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09 * glassEdgeStrength), lineWidth: 1)
            }

            if variant == .variantD {
                RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    .padding(.horizontal, 12)
            }

            if variant == .variantE {
                LinearGradient(
                    colors: [Color.white.opacity(0.09), .clear, Color.white.opacity(0.04)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(0.5)
            }

            content
                .padding(contentPadding)
        }
        .frame(height: canvasHeight)
        .clipShape(RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        }
        .shadow(color: canvasShadow, radius: 16, y: 8)
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .variantA:
            floatingLayout
        case .variantB:
            splitRailLayout
        case .variantC:
            compactLayout
        case .variantD:
            shelfLayout
        case .variantE:
            minimalLayout
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text("What to check")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
            ForEach(variant.layoutChecklistItems, id: \.self) { item in
                HStack(alignment: .top, spacing: FFSpacing.xs) {
                    Circle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(item)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var floatingLayout: some View {
        VStack(alignment: .leading, spacing: FFSpacing.md * buttonSpacingTuning) {
            summaryRow

            VStack(alignment: .leading, spacing: FFSpacing.sm * buttonSpacingTuning) {
                projectChipRow
                durationRail
                stepperRow
            }
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.sm)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10))
            }

            actionRow
        }
    }

    private var splitRailLayout: some View {
        HStack(alignment: .center, spacing: FFSpacing.md * buttonSpacingTuning) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                summaryRow
                projectChipRow
                textFooter
            }
            .frame(maxWidth: 160, alignment: .leading)
            .padding(.trailing, FFSpacing.xs)

            VStack(alignment: .leading, spacing: FFSpacing.sm * buttonSpacingTuning) {
                durationRail
                stepperRow
                actionRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm * 0.8 * buttonSpacingTuning) {
            HStack(alignment: .firstTextBaseline) {
                summaryRow
                Spacer()
                textFooter
            }

            HStack(spacing: FFSpacing.sm * buttonSpacingTuning) {
                projectChipRow
                Spacer(minLength: 0)
                durationRail
            }

            stepperRow
            actionRow
        }
    }

    private var shelfLayout: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                summaryRow
                Spacer()
                scenarioBadge
            }

            HStack(alignment: .top, spacing: FFSpacing.sm * buttonSpacingTuning) {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    projectChipRow
                    textFooter
                }
                .frame(maxWidth: 140, alignment: .leading)

                VStack(alignment: .leading, spacing: FFSpacing.sm * buttonSpacingTuning) {
                    durationRail
                    stepperRow
                    actionRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var minimalLayout: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm * 0.9 * buttonSpacingTuning) {
            HStack(alignment: .firstTextBaseline) {
                summaryRow
                Spacer()
                textFooter
            }

            HStack(spacing: FFSpacing.sm * buttonSpacingTuning) {
                projectChipRow
                Spacer(minLength: 0)
                scenarioBadge
            }

            VStack(alignment: .leading, spacing: FFSpacing.sm * buttonSpacingTuning) {
                durationRail
                stepperRow
                actionRow
            }
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

    private var summaryRow: some View {
        HStack(spacing: FFSpacing.xs) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text("Menu slider")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
            Spacer()
            Text(snapshot.projectName)
                .font(FFType.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var projectChipRow: some View {
        HStack(spacing: FFSpacing.xs) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(snapshot.projectName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, FFSpacing.sm)
        .padding(.vertical, FFSpacing.xs)
        .background(Color.white.opacity(0.11), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.08))
        }
    }

    private var durationRail: some View {
        HStack(spacing: FFSpacing.xs * buttonSpacingTuning) {
            ForEach(["15m", "25m", "45m", "60m"], id: \.self) { label in
                durationPill(label)
            }
        }
        .padding(.horizontal, FFSpacing.xxs)
    }

    private func durationPill(_ label: String) -> some View {
        Button {} label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, FFSpacing.xs * 1.4)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(durationTint(for: label))
    }

    private var stepperRow: some View {
        HStack(spacing: FFSpacing.sm * buttonSpacingTuning) {
            Button {} label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.white.opacity(0.45))

            Text(isExpanded ? "20 min" : "15 min")
                .font(.system(size: 17 * motionIntensity, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.white.opacity(0.45))
        }
    }

    private var actionRow: some View {
        HStack(spacing: FFSpacing.xs * buttonSpacingTuning) {
            Button(snapshot.primaryAction) {}
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(primaryActionTint)
                .scaleEffect(buttonProminence + (hoverPreview ? 0.02 : 0.0) - (pressAmount * 0.03))

            Button(snapshot.secondaryAction) {}
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.white.opacity(buttonSecondaryOpacity))
        }
        .animation(animation, value: hoverPreview)
        .animation(animation, value: pressAmount)
    }

    private var textFooter: some View {
        Text(snapshot.footer)
            .font(FFType.meta)
            .foregroundStyle(.secondary)
            .lineLimit(2)
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

            case .texture:
                VStack(spacing: 12) {
                    ForEach(0..<12, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.05) : Color.white.opacity(0.015))
                            .frame(height: 10)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var surfaceBackground: some View {
        ZStack {
            backdropScene
            Rectangle().fill(materialFill)
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

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

            if variant == .variantD {
                LinearGradient(
                    colors: [Color.white.opacity(0.06), .clear, Color.white.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.screen)
            }

            if variant == .variantE {
                RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .padding(10)
            }
        }
    }

    private var canvasHeight: CGFloat {
        switch variant {
        case .variantA: return 320
        case .variantB: return 292
        case .variantC: return 272
        case .variantD: return 284
        case .variantE: return 262
        }
    }

    private var contentPadding: EdgeInsets {
        switch variant {
        case .variantA: return EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        case .variantB: return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case .variantC: return EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        case .variantD: return EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        case .variantE: return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        }
    }

    private var ringStyle: StrokeStyle {
        switch variant {
        case .variantA: return StrokeStyle(lineWidth: 7.5, lineCap: .round, lineJoin: .round)
        case .variantB: return StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round)
        case .variantC: return StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
        case .variantD: return StrokeStyle(lineWidth: 5.8, lineCap: .round, lineJoin: .round)
        case .variantE: return StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round)
        }
    }

    private var ringWeight: Font.Weight {
        switch variant {
        case .variantA: return .light
        case .variantB: return .thin
        case .variantC: return .ultraLight
        case .variantD: return .light
        case .variantE: return .thin
        }
    }

    private var ringScale: CGFloat {
        switch variant {
        case .variantA: return 1.0
        case .variantB: return 0.84
        case .variantC: return 0.72
        case .variantD: return 0.90
        case .variantE: return 0.66
        }
    }

    private var effectRingScale: CGFloat {
        switch variant {
        case .variantA: return 0.95
        case .variantB: return 0.82
        case .variantC: return 0.74
        case .variantD: return 0.88
        case .variantE: return 0.68
        }
    }

    private var motionRingScale: CGFloat {
        switch variant {
        case .variantA: return 0.95
        case .variantB: return 0.85
        case .variantC: return 0.76
        case .variantD: return 0.88
        case .variantE: return 0.70
        }
    }

    private var motionHoverScale: CGFloat {
        switch variant {
        case .variantA: return 1.06
        case .variantB: return 1.03
        case .variantC: return 1.02
        case .variantD: return 1.04
        case .variantE: return 1.015
        }
    }

    private var motionPressScale: CGFloat {
        switch variant {
        case .variantA: return 0.96
        case .variantB: return 0.97
        case .variantC: return 0.98
        case .variantD: return 0.965
        case .variantE: return 0.985
        }
    }

    private var motionClosedYOffset: CGFloat {
        switch variant {
        case .variantA: return 6
        case .variantB: return 4
        case .variantC: return 3
        case .variantD: return 5
        case .variantE: return 2
        }
    }

    private var previewTimerState: TimerState {
        .idle
    }

    private var primaryActionTint: Color {
        switch variant {
        case .variantA: return snapshot.highlight.opacity(0.93)
        case .variantB: return snapshot.highlight.opacity(0.85)
        case .variantC: return snapshot.highlight.opacity(0.78)
        case .variantD: return snapshot.highlight.opacity(0.88)
        case .variantE: return snapshot.highlight.opacity(0.75)
        }
    }

    private func durationTint(for label: String) -> Color {
        if label == "25m" {
            return snapshot.highlight.opacity(0.92)
        }
        if label == "15m" {
            return .white.opacity(0.54)
        }
        if label == "45m" {
            return .white.opacity(0.48)
        }
        return .white.opacity(0.45)
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

    private var backgroundMaterialOpacity: Double {
        switch variant {
        case .variantA: return 0.90
        case .variantB: return 0.94
        case .variantC: return 0.98
        case .variantD: return 0.92
        case .variantE: return 0.96
        }
    }

    private var gradientColors: [Color] {
        switch variant {
        case .variantA:
            return [Color.white.opacity(highlightStrength * 0.75), Color.white.opacity(0.03), Color.black.opacity(0.05)]
        case .variantB:
            return [Color.white.opacity(highlightStrength * 0.45), Color.white.opacity(0.02), Color.black.opacity(0.05)]
        case .variantC:
            return [Color.white.opacity(highlightStrength * 0.3), Color.white.opacity(0.01), Color.black.opacity(0.04)]
        case .variantD:
            return [Color.white.opacity(highlightStrength * 0.5), Color.white.opacity(0.015), Color.black.opacity(0.05)]
        case .variantE:
            return [Color.white.opacity(highlightStrength * 0.22), Color.white.opacity(0.01), Color.black.opacity(0.03)]
        }
    }

    private var canvasShadow: Color {
        switch variant {
        case .variantA: return .black.opacity(0.16)
        case .variantB: return .black.opacity(0.14)
        case .variantC: return .black.opacity(0.12)
        case .variantD: return .black.opacity(0.13)
        case .variantE: return .black.opacity(0.11)
        }
    }

    private var effectFill: some ShapeStyle {
        materialFill
    }

    private var effectStroke: Color {
        .white.opacity(0.14 * glassEdgeStrength)
    }

    private var effectGloss: some ShapeStyle {
        LinearGradient(
            colors: [
                .white.opacity(0.12 * glassBloomStrength),
                .clear,
                .white.opacity(0.05 * glassBloomStrength)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var effectShadow: Color {
        .black.opacity(0.16)
    }

    private var motionPanelFill: some ShapeStyle {
        materialFill
    }

    private var motionPanelStroke: Color {
        .white.opacity(0.12)
    }

    private var motionShadow: Color {
        .black.opacity(0.15)
    }
}
