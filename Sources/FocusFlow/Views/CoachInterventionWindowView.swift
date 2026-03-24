import SwiftUI

struct CoachInterventionWindowView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.dismissWindow) private var dismissWindow

    /// When set, the action buttons are replaced by reason chips for this action
    @State private var pendingAction: FocusCoachQuickAction? = nil
    @State private var selectedSkipReason: FocusCoachSkipReason? = nil
    @State private var coachMessage: CoachMessage? = nil

    private var decision: FocusCoachDecision? {
        timerVM.activeCoachInterventionDecision
    }

    private var titleText: String {
        if pendingAction != nil {
            return "Quick — what's up?"
        }
        if timerVM.state == .idle {
            return "Let's start focus now"
        }
        return "Return to focus now"
    }

    private var displayTitle: String {
        if pendingAction != nil { return "Quick — what's up?" }
        return coachMessage?.headline ?? titleText
    }

    // MARK: - Context Banner (derived from unified signal — never re-resolves context independently)

    private var bannerContent: (icon: String, label: String)? {
        guard let msg = coachMessage,
              let icon = msg.bannerIcon,
              let label = msg.bannerLabel else { return nil }
        return (icon, label)
    }

    var body: some View {
        VStack(spacing: 0) {
            LiquidGlassPanel(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    // Context card (amber pill) — always coherent with headline
                    if let banner = bannerContent, pendingAction == nil {
                        HStack(spacing: 5) {
                            Image(systemName: banner.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(banner.label)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(LiquidDesignTokens.Spectral.amber.opacity(0.12))
                                .overlay(Capsule().strokeBorder(
                                    LiquidDesignTokens.Spectral.amber.opacity(0.25), lineWidth: 0.5))
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }

                    header

                    if pendingAction == nil {
                        // Body text — personalised or fallback
                        if let body = coachMessage?.body {
                            Text(body)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        } else if let message = decision?.message, !message.isEmpty {
                            Text(message)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        } else {
                            Text("Time to refocus — your next session is waiting.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }

                        // Quote block
                        if let quote = coachMessage?.quote {
                            quoteBlock(quote)
                                .transition(.opacity)
                        }
                    }

                    if let action = pendingAction {
                        skipReasonPanel(for: action)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                removal: .opacity
                            ))
                    } else {
                        actionStack
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                            ))
                    }
                }
                .padding(18)
                .animation(FFMotion.section, value: pendingAction == nil)
            }
        }
        .frame(width: 360)
        .padding(12)
        .onAppear {
            bringToFront()
            if let ctx = decision?.context {
                coachMessage = FocusCoachMessageBuilder.build(context: ctx, sessionSeed: timerVM.todaySessionCount)
            }
        }
        .onChange(of: decision?.kind) { _, _ in
            if let ctx = decision?.context {
                coachMessage = FocusCoachMessageBuilder.build(context: ctx, sessionSeed: timerVM.todaySessionCount)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pendingAction != nil ? "questionmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(pendingAction != nil
                    ? LiquidDesignTokens.Spectral.amber
                    : LiquidDesignTokens.Spectral.salmon)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text("Focus Coach")
                    .font(LiquidDesignTokens.Typography.labelSmall)
                    .tracking(1.2)
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                Text(displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Spacer()
        }
    }

    // MARK: - Quote Block

    @ViewBuilder
    private func quoteBlock(_ quote: FocusCoachQuote) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\u{201C}\(quote.text)\u{201D}")
                .font(.system(size: 12, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
            Text("— \(quote.attribution)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Primary Action Stack

    private var actionStack: some View {
        VStack(spacing: 8) {
            LiquidActionButton(
                title: timerVM.state == .idle ? "Start Focus Now" : "Return to Focus",
                icon: timerVM.state == .idle ? "play.fill" : "arrow.uturn.backward",
                role: .primary,
                tint: LiquidDesignTokens.Spectral.primaryContainer
            ) {
                timerVM.handleCoachAction(timerVM.state == .idle ? .startFocusNow : .returnNow)
                dismiss()
            }

            if allows(.cleanRestart5m) {
                LiquidActionButton(
                    title: "Restart with 5m",
                    icon: "arrow.clockwise",
                    role: .secondary
                ) {
                    timerVM.handleCoachAction(.cleanRestart5m)
                    dismiss()
                }
            }

            if allows(.snooze10m) {
                LiquidActionButton(
                    title: "Snooze",
                    icon: "moon.zzz.fill",
                    role: .secondary
                ) {
                    withAnimation(FFMotion.section) {
                        pendingAction = .snooze10m
                    }
                }
            }

            if allows(.blockForProject) {
                LiquidActionButton(
                    title: "Block for this project",
                    icon: "shield.lefthalf.filled",
                    role: .secondary
                ) {
                    timerVM.handleCoachAction(.blockForProject)
                    dismiss()
                }
            }

            if timerVM.settings?.coachAllowSkipAction == true, allows(.skipCheck) {
                Button {
                    withAnimation(FFMotion.section) {
                        pendingAction = .skipCheck
                    }
                } label: {
                    Text("Skip this check")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Skip this coach check")
            }
        }
    }

    // MARK: - Inline Skip Reason Panel

    @ViewBuilder
    private func skipReasonPanel(for action: FocusCoachQuickAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Back + prompt row
            HStack(spacing: 0) {
                Button {
                    withAnimation(FFMotion.section) { pendingAction = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("What's really going on?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

                Spacer()
            }

            // Group 1: Genuine reasons
            VStack(alignment: .leading, spacing: 7) {
                groupLabel("GENUINE REASON")
                FlowLayout(spacing: 7) {
                    ForEach(FocusCoachSkipReason.genuineReasons, id: \.rawValue) { reason in
                        skipReasonChip(reason, action: action)
                    }
                }
            }

            // Group 2: Being honest
            VStack(alignment: .leading, spacing: 7) {
                groupLabel("BEING HONEST")
                FlowLayout(spacing: 7) {
                    ForEach(FocusCoachSkipReason.honestReasons, id: \.rawValue) { reason in
                        skipReasonChip(reason, action: action)
                    }
                }
            }

            // Escape hatch
            HStack {
                Spacer()
                Button { commitAction(action, reason: nil) } label: {
                    Text("Skip without reason →")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this check without giving a reason")
            }
        }
    }

    @ViewBuilder
    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.5))
    }

    @ViewBuilder
    private func skipReasonChip(_ reason: FocusCoachSkipReason, action: FocusCoachQuickAction) -> some View {
        let isSelected = selectedSkipReason == reason
        let accentColor: Color = reason.isLegitimate
            ? LiquidDesignTokens.Spectral.electricBlue  // genuine → teal
            : Color.white.opacity(0.6)                  // honest → neutral (amber reserved for context pill/warnings)

        Button {
            withAnimation(FFMotion.control) { selectedSkipReason = reason }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                commitAction(action, reason: reason)
            }
        } label: {
            HStack(spacing: 5) {
                Text(reason.icon)
                    .font(.system(size: 11))
                Text(reason.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? accentColor : LiquidDesignTokens.Surface.onSurfaceMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isSelected
                        ? accentColor.opacity(0.14)
                        : (reason.isLegitimate ? Color.white.opacity(0.08) : Color.white.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(
                        isSelected ? accentColor.opacity(0.35) : Color.white.opacity(0.09),
                        lineWidth: 0.5))
            }
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .frame(minHeight: 44, alignment: .center)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(FFMotion.control, value: isSelected)
        .accessibilityLabel(reason.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Helpers

    private func commitAction(_ action: FocusCoachQuickAction, reason: FocusCoachSkipReason?) {
        timerVM.handleCoachAction(action, skipReason: reason)
        dismiss()
    }

    private func allows(_ action: FocusCoachQuickAction) -> Bool {
        decision?.suggestedActions.contains(action) ?? false
    }

    private func dismiss() {
        timerVM.dismissCoachInterventionWindow()
        dismissWindow(id: "coach-intervention")
    }

    private func bringToFront() {
        // Activate app and promote the coach window in a single pass.
        // Use window identifier only (not localized title) for reliable matching.
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows
                where window.identifier?.rawValue.contains("coach-intervention") == true {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}
