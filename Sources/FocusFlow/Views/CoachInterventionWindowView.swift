import SwiftUI

struct CoachInterventionWindowView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.dismissWindow) private var dismissWindow

    /// When set, the action buttons are replaced by reason chips for this action
    @State private var pendingAction: FocusCoachQuickAction? = nil
    @State private var selectedSkipReason: FocusCoachSkipReason? = nil
    @State private var confirmedSkipReason: FocusCoachSkipReason? = nil
    @State private var isConfirming: Bool = false
    @State private var coachMessage: CoachMessage? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        return interventionTitle
    }

    private var interventionTitle: String {
        switch decision?.kind {
        case .strongPrompt:
            return "Off-plan right now?"
        default:
            return "Planned or drift?"
        }
    }

    private var effectiveActions: [FocusCoachQuickAction] {
        decision?.suggestedActions ?? []
    }

    private var startAction: FocusCoachQuickAction {
        if allows(.startFocusNow) { return .startFocusNow }
        return .cleanRestart5m
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
                                .accessibilityHidden(true)
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

                        // Quote block intentionally omitted from intervention critical path (spec §8)

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
                .animation(reduceMotion ? nil : FFMotion.section, value: pendingAction == nil)
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
                .accessibilityHidden(true)

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
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    // MARK: - Primary Action Stack

    private var actionStack: some View {
        VStack(spacing: 8) {
            // Primary: Start 5m rescue block
            LiquidActionButton(
                title: startAction == .startFocusNow ? "Start Focus Now" : "Start 5m rescue block",
                icon: startAction == .startFocusNow ? "play.fill" : "arrow.clockwise",
                role: .primary,
                tint: LiquidDesignTokens.Spectral.primaryContainer
            ) {
                timerVM.handleCoachAction(startAction)
                dismiss()
            }
            .opacity(allows(startAction) ? 1 : 0.4)
            .disabled(!allows(startAction))

            if allows(.snooze10m) {
                LiquidActionButton(
                    title: "Remind me again",
                    icon: "moon.zzz.fill",
                    role: .secondary
                ) {
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) {
                        pendingAction = .snooze10m
                    }
                }
            }

            if allows(.skipCheck) {
                LiquidActionButton(
                    title: "Not now",
                    icon: "forward.end.fill",
                    role: .secondary
                ) {
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) {
                        pendingAction = .skipCheck
                    }
                }
            }

            if allows(.isPlanned) {
                LiquidActionButton(
                    title: "This is genuine / planned",
                    icon: "checkmark.circle",
                    role: .secondary
                ) {
                    timerVM.handleCoachAction(.isPlanned)
                    dismiss()
                }
            }

            // Secondary: Mark off-duty for now
            LiquidActionButton(
                title: "Mark off-duty for now",
                icon: "moon.fill",
                role: .secondary
            ) {
                timerVM.handleCoachAction(.markOffDuty)
                dismiss()
            }
            .opacity(allows(.markOffDuty) ? 1 : 0.4)
            .disabled(!allows(.markOffDuty))

            // Conditional: block recommendation when threshold met
            if allows(.blockForProject) {
                LiquidActionButton(
                    title: "Block these for this project",
                    icon: "shield.lefthalf.filled",
                    role: .secondary
                ) {
                    timerVM.handleCoachAction(.blockForProject)
                    dismiss()
                }
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
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) { pendingAction = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .accessibilityHidden(true)
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
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.control) { selectedSkipReason = reason }
            confirmedSkipReason = reason
            isConfirming = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
            .scaleEffect(isConfirming && confirmedSkipReason == reason ? 0.96 : 1.0)
            .animation(reduceMotion ? nil : FFMotion.commit, value: isConfirming)
            .background(
                Circle()
                    .fill(skipPulseColor(for: confirmedSkipReason).opacity(confirmedSkipReason == reason ? 0.3 : 0))
                    .blur(radius: 6)
                    .scaleEffect(confirmedSkipReason == reason ? 1.3 : 0.8)
                    .animation(reduceMotion ? nil : FFMotion.reward, value: confirmedSkipReason)
            )
            .frame(minHeight: 44, alignment: .center)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : FFMotion.control, value: isSelected)
        .accessibilityLabel(reason.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Helpers

    private func skipPulseColor(for reason: FocusCoachSkipReason?) -> Color {
        guard let reason else { return .clear }
        return reason.isLegitimate ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.amber
    }

    private func commitAction(_ action: FocusCoachQuickAction, reason: FocusCoachSkipReason?) {
        timerVM.handleCoachAction(action, skipReason: reason)
        dismiss()
    }

    private func allows(_ action: FocusCoachQuickAction) -> Bool {
        effectiveActions.contains(action)
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
