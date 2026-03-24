import SwiftUI
import SwiftData

// MARK: - Completion Stage

private enum CompletionStage { case earned, next }

struct SessionCompleteWindowView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.dismissWindow) private var dismissWindow
    @Query private var allSettings: [AppSettings]

    // Two-stage focus flow
    @State private var stage: CompletionStage = .earned
    @State private var appeared = false

    // Reflection fields (persisted across stages)
    @State private var selectedMood: FocusMood? = nil
    @State private var carryForwardNote: String = ""
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []
    @State private var selectedReminderItems: [RemindersService.ReminderItem] = []
    @State private var showReminderPicker = false
    @State private var hasHandledAction = false
    @State private var capturedReason: FocusCoachReason? = nil

    private var settings: AppSettings? { allSettings.first }

    private var isBreakCompletion: Bool { timerVM.lastCompletionWasBreak }

    /// Resolved earned context — prefers durable `completedBlockContext`, falls back to legacy session info.
    private var earnedContext: (minutes: Int, projectName: String)? {
        if let ctx = timerVM.completedBlockContext {
            return (ctx.durationMinutes, ctx.projectName)
        }
        if let s = timerVM.lastCompletedFocusSession {
            return (Int(s.actualDuration / 60), s.label)
        }
        if let dur = timerVM.lastCompletedDuration {
            return (Int(dur / 60), timerVM.lastCompletedLabel ?? "Focus")
        }
        return nil
    }

    var body: some View {
        Group {
            if isBreakCompletion {
                breakContent
            } else {
                focusContent
            }
        }
        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
        .interactiveDismissDisabled()
        .onAppear {
            bringWindowToFront()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appeared = true }
        }
        .onDisappear {
            if !hasHandledAction && timerVM.isManualStop && timerVM.showSessionComplete {
                timerVM.preserveManualStop()
            }
        }
    }

    // MARK: - Focus Completion (two-stage)

    private var focusContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    if stage == .earned {
                        earnedStage
                    } else {
                        nextStage
                    }
                }
                .padding(24)
                .animation(.easeInOut(duration: 0.22), value: stage)
            }
            footerBar
        }
        .frame(width: 480)
    }

    // MARK: Stage 1 — Earned

    private var earnedStage: some View {
        VStack(spacing: 20) {
            earnedBadge

            // Coach reason capture or confirmation pill
            if timerVM.showCoachReasonSheet {
                coachReasonSection
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.97))
                    ))
            } else if let reason = capturedReason {
                reasonConfirmationPill(reason)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                        removal: .opacity
                    ))
            }

            carryForwardSection
            moodSection
            remindersSection
            continueButton
        }
        .animation(FFMotion.section, value: timerVM.showCoachReasonSheet)
    }

    private var earnedBadge: some View {
        VStack(spacing: 12) {
            // Animated glow + icon
            ZStack {
                Circle()
                    .fill(LiquidDesignTokens.Spectral.mint.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .blur(radius: appeared ? 14 : 0)
                    .animation(.easeOut(duration: 0.5), value: appeared)

                Image(systemName: timerVM.isManualStop ? "stop.circle.fill" : "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        timerVM.isManualStop
                            ? LiquidDesignTokens.Spectral.salmon
                            : LiquidDesignTokens.Spectral.amber
                    )
                    .accessibilityHidden(true)
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: appeared)

            // Earned time headline
            if let ctx = earnedContext {
                VStack(spacing: 4) {
                    Text(timerVM.isManualStop ? "\(ctx.minutes)m focused" : "✦ \(ctx.minutes)m earned")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            timerVM.isManualStop
                                ? LiquidDesignTokens.Spectral.salmon
                                : LiquidDesignTokens.Spectral.amber
                        )
                    Text(ctx.projectName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                        .lineLimit(1)
                }
            } else {
                Text(timerVM.isManualStop ? "Session Ended Early" : "Session Complete")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }

            // Today's stats
            let blockCount = timerVM.todaySessionCount
            let totalMins = Int(timerVM.todayFocusTime / 60)
            Text("\(blockCount) block\(blockCount == 1 ? "" : "s") today · \(totalMins)m total")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)

            // Calendar save confirmation
            if let eventId = timerVM.lastCompletedSession?.calendarEventId, !eventId.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Saved to Calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.10)))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if !timerVM.isManualStop {
                Text("Ready for another block?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                    .italic()
            }
        }
        .padding(.top, 8)
    }

    private var carryForwardSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrackedLabel(
                text: timerVM.isManualStop ? "What Did You Finish?" : "Carry-Forward Note",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )

            ZStack(alignment: .topLeading) {
                if carryForwardNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(timerVM.isManualStop ? "Log your wins — one per line..." : "What to pick up next (optional)...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $carryForwardNote)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .frame(minHeight: 72, maxHeight: 120)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .accessibilityLabel(timerVM.isManualStop ? "Achievements" : "Carry-forward note")
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
    }

    private var continueButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                stage = .next
            }
        } label: {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
        .accessibilityLabel("Continue to choose next action")
    }

    // MARK: Stage 2 — Next

    private var nextStage: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("What's next?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .padding(.top, 8)
                if let ctx = earnedContext {
                    Text("\(ctx.minutes)m · \(ctx.projectName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }
            }

            splitSection

            GlassEffectContainer {
                VStack(spacing: 8) {
                    // Primary: Start next block
                    GradientCTAButton(
                        title: "Start Next Block",
                        icon: "play.fill",
                        gradient: LiquidDesignTokens.Gradient.breakStart
                    ) {
                        saveAndDismiss(action: .continueFocusing)
                    }
                    .accessibilityLabel("Start next focus block")

                    // Take 5m reset (short break via standard break action)
                    LiquidActionButton(
                        title: "Take 5m Reset",
                        icon: "timer",
                        role: .secondary
                    ) {
                        saveAndDismiss(action: .takeBreak(duration: 300))
                    }
                    .accessibilityLabel("Take a 5 minute reset break")

                    // Take full break
                    LiquidActionButton(
                        title: "Take Full Break",
                        icon: "cup.and.saucer.fill",
                        role: .secondary
                    ) {
                        saveAndDismiss(action: .takeBreak(duration: nil))
                    }
                    .accessibilityLabel("Take a full break")

                    // End with today's progress
                    GradientCTAButton(
                        title: timerVM.cycleProgress >= 1.0 ? "Complete Focus Block 🎉" : "End with Today's Progress",
                        icon: timerVM.cycleProgress >= 1.0 ? "checkmark.seal.fill" : "checkmark.circle.fill",
                        gradient: LiquidDesignTokens.Gradient.cycleCompletion(progress: timerVM.cycleProgress)
                    ) {
                        saveAndDismiss(action: .endSession)
                    }
                    .accessibilityLabel("End session with today's progress")

                    // Discard — only for manual stops
                    if timerVM.isManualStop {
                        Button {
                            hasHandledAction = true
                            timerVM.discardManualStop()
                            dismissWindow(id: "session-complete")
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Discard Session")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                        .accessibilityLabel("Discard this manual session")
                    }
                }
            }
        }
    }

    // MARK: - Coach Reason

    private var coachReasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(
                text: "What Happened?",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )
            Text("Help your coach understand why this session ended early")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            FocusCoachReasonChipSheet(
                anomalyKind: timerVM.pendingReasonKind,
                onSelect: { reason in
                    capturedReason = reason
                    timerVM.recordCoachReason(kind: timerVM.pendingReasonKind, reason: reason)
                    timerVM.showCoachReasonSheet = false
                },
                onSnooze: {
                    timerVM.showCoachReasonSheet = false
                },
                onDismiss: {
                    timerVM.recordCoachReason(kind: timerVM.pendingReasonKind, reason: nil)
                    timerVM.showCoachReasonSheet = false
                }
            )
        }
    }

    @ViewBuilder
    private func reasonConfirmationPill(_ reason: FocusCoachReason) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
            Text("Reason captured: **\(reason.displayName)**")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.15), lineWidth: 0.5))
        )
    }

    // MARK: - Mood

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(
                text: "How Was Your Focus?",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )
            MoodSelector(selectedMood: $selectedMood, style: .regular)
        }
    }

    // MARK: - Project Split

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(
                text: "Project Allocation",
                font: .system(size: 12, weight: .semibold),
                tracking: 1.8
            )

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSplits.toggle()
                    if showSplits && splits.isEmpty {
                        let totalMins = Int((timerVM.lastCompletedDuration ?? 0) / 60)
                        splits = [TimeSplitView.SplitEntry(
                            project: timerVM.selectedProject,
                            customLabel: timerVM.customLabel,
                            minutes: totalMins
                        )]
                    }
                }
            } label: {
                HStack {
                    Image(systemName: showSplits ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                        .font(.system(size: 13))
                    Text("Split across projects")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: showSplits ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityLabel(showSplits ? "Collapse project split" : "Split across projects")
            .accessibilityHint("Allocate session time across multiple projects")

            if showSplits {
                TimeSplitView(
                    totalDuration: timerVM.lastCompletedDuration ?? 0,
                    splits: $splits
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TrackedLabel(
                    text: "Linked Reminders",
                    font: .system(size: 11, weight: .semibold),
                    tracking: 1.8
                )
                Spacer()
                if settings?.remindersIntegrationEnabled == true {
                    Button {
                        showReminderPicker = true
                    } label: {
                        Label("Attach", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach reminder")
                }
            }

            if settings?.remindersIntegrationEnabled != true {
                Text("Enable Reminders sync in Settings to link tasks.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if selectedReminderItems.isEmpty {
                Text("No reminders linked")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(selectedReminderItems, id: \.id) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "checklist")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.blue)
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                selectedReminderItems.removeAll(where: { $0.id == item.id })
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Remove reminder")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showReminderPicker) {
            ReminderSelectionSheet(
                selectedListId: settings?.selectedReminderListId,
                initialSelectedIds: Set(selectedReminderItems.map(\.id))
            ) { chosen in
                selectedReminderItems = chosen
            }
        }
    }

    // MARK: - Break Completion

    private var breakContent: some View {
        VStack(spacing: 12) {
            breakHeaderSection
            if timerVM.showCoachReasonSheet {
                breakReasonSection
            }
            breakActionsSection
            // Classification chips — only shown when overrun exceeds 60 seconds
            if (timerVM.breakEpisodeContext?.overrunSeconds ?? 0) > 60 {
                breakRecoveryChips
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var breakHeaderSection: some View {
        VStack(spacing: 10) {
            let isOverrun = (timerVM.breakEpisodeContext?.overrunSeconds ?? 0) > 60
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 40))
                .foregroundStyle(isOverrun ? LiquidDesignTokens.Spectral.amber : .blue)
                .accessibilityHidden(true)

            Text(isOverrun ? "Break ran long" : "Reset complete")
                .font(.system(size: 20, weight: .semibold))

            if timerVM.isOvertime {
                LiquidMetricCard(
                    title: "Overtime",
                    value: timerVM.overtimeTimeString,
                    icon: "exclamationmark.triangle.fill",
                    color: timerVM.overtimeSeconds > 120 ? .red : .orange
                )
                .frame(maxWidth: 180)
            }

            // Spec invariant: always show last earned block
            if let ctx = timerVM.completedBlockContext ?? timerVM.breakEpisodeContext?.earnedBlock {
                VStack(spacing: 3) {
                    Text("Last earned block")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(ctx.durationMinutes)m · \(ctx.projectName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LiquidDesignTokens.Spectral.electricBlue.opacity(0.1)))
            }
        }
        .padding(.top, 8)
    }

    private var breakActionsSection: some View {
        let overrun = timerVM.breakEpisodeContext?.overrunSeconds ?? 0
        return GlassEffectContainer {
            VStack(spacing: 8) {
                LiquidActionButton(
                    title: "Start Next Block",
                    icon: "play.fill",
                    role: .primary,
                    tint: .blue
                ) {
                    hasHandledAction = true
                    timerVM.continueAfterCompletion(action: .continueFocusing)
                    dismissWindow(id: "session-complete")
                }
                .accessibilityLabel("Start next focus block")

                // Short-overrun extension option
                if overrun > 0 && overrun <= 60 {
                    LiquidActionButton(
                        title: "Take 1 More Minute",
                        icon: "clock.badge.plus",
                        role: .secondary
                    ) {
                        hasHandledAction = true
                        timerVM.continueAfterCompletion(action: .continueOvertime)
                        dismissWindow(id: "session-complete")
                    }
                    .accessibilityLabel("Take 1 more minute")
                }

                LiquidActionButton(
                    title: "End with Progress",
                    icon: "stop.fill",
                    role: .secondary
                ) {
                    hasHandledAction = true
                    timerVM.continueAfterCompletion(action: .endSession)
                    dismissWindow(id: "session-complete")
                }
                .accessibilityLabel("End break and keep progress")
            }
        }
    }

    /// Classification chips shown when break overrun exceeds 60 seconds (amber, compact, no motion).
    private var breakRecoveryChips: some View {
        VStack(spacing: 8) {
            Text("How's the break going?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                recoveryChipButton("Still recovering") {
                    timerVM.classifyBreakRecovery(.stillRecovering)
                }
                recoveryChipButton("Done for now") {
                    timerVM.classifyBreakRecovery(.doneForNow)
                    hasHandledAction = true
                    dismissWindow(id: "session-complete")
                }
                recoveryChipButton("Got distracted") {
                    timerVM.classifyBreakRecovery(.gotDistracted)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func recoveryChipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LiquidDesignTokens.Spectral.amber.opacity(0.15))
                        .overlay(Capsule()
                            .strokeBorder(LiquidDesignTokens.Spectral.amber.opacity(0.3), lineWidth: 0.5))
                )
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .foregroundStyle(LiquidDesignTokens.Spectral.amber)
        .accessibilityLabel(title)
    }

    private var breakReasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(
                text: "What Extended Your Break?",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )
            Text("This helps your coach distinguish legitimate interruptions from avoidable drift.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            FocusCoachReasonChipSheet(
                anomalyKind: .breakOverrun,
                onSelect: { reason in
                    timerVM.recordCoachReason(kind: .breakOverrun, reason: reason)
                    timerVM.showCoachReasonSheet = false
                },
                onSnooze: {
                    timerVM.showCoachReasonSheet = false
                },
                onDismiss: {
                    timerVM.recordCoachReason(kind: .breakOverrun, reason: nil)
                    timerVM.showCoachReasonSheet = false
                }
            )
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            TrackedLabel(
                text: "FocusFlow macOS",
                font: .system(size: 10, weight: .medium),
                color: LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.5),
                tracking: 1.5
            )

            Spacer()

            Text(formattedTodayTotal)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Spectral.electricBlue.opacity(0.7))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(LiquidDesignTokens.Surface.materialOverlay)
        )
    }

    private var formattedTodayTotal: String {
        let total = timerVM.todayFocusTime
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 {
            return "TODAY'S TOTAL: \(hours)H \(minutes)M"
        } else {
            return "TODAY'S TOTAL: \(minutes)M"
        }
    }

    // MARK: - Actions

    private func saveAndDismiss(action: PostCompletionAction) {
        hasHandledAction = true
        Task { @MainActor in
            await timerVM.saveReflection(
                mood: selectedMood,
                achievement: carryForwardNote.isEmpty ? nil : carryForwardNote,
                reminderIdsToComplete: selectedReminderItems.map(\.id),
                splits: showSplits ? splits : nil
            )
            timerVM.continueAfterCompletion(action: action)
            dismissWindow(id: "session-complete")
        }
    }

    // MARK: - Helpers

    private func bringWindowToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let allWindows = NSApplication.shared.windows
            for window in allWindows where window.identifier?.rawValue.contains("session-complete") == true {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                window.center()
                return
            }
            // Fallback: newest non-panel, non-stats window
            if let window = allWindows.last(where: {
                !$0.title.isEmpty && $0.title != "FocusFlow" && !($0 is NSPanel) && $0.isVisible
            }) {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
        }
    }
}
