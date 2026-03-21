import SwiftUI
import SwiftData

struct SessionCompleteWindowView: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.dismissWindow) private var dismissWindow
    @Query private var allSettings: [AppSettings]
    @State private var selectedMood: FocusMood? = nil
    @State private var achievement: String = ""
    @State private var showSplits = false
    @State private var splits: [TimeSplitView.SplitEntry] = []
    @State private var selectedReminderItems: [RemindersService.ReminderItem] = []
    @State private var showReminderPicker = false

    private var settings: AppSettings? { allSettings.first }

    private var isBreakCompletion: Bool {
        timerVM.lastCompletedSession?.type != .focus
    }

    var body: some View {
        Group {
            if isBreakCompletion {
                breakContent
            } else {
                focusContent
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            bringWindowToFront()
        }
        .onDisappear {
            if timerVM.isManualStop && timerVM.showSessionComplete {
                timerVM.discardManualStop()
            }
        }
    }

    // MARK: - Focus Completion

    private var focusContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                focusHeaderSection
                moodSection
                achievementSection
                focusActionsSection
                splitSection
                remindersSection
            }
            .padding(24)

            footerBar
        }
        .frame(width: 480)
    }

    private var focusHeaderSection: some View {
        VStack(spacing: 12) {
            Image(systemName: timerVM.isManualStop ? "stop.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(timerVM.isManualStop
                    ? LiquidDesignTokens.Spectral.salmon
                    : LiquidDesignTokens.Spectral.primaryContainer)
                .accessibilityHidden(true)

            Text(timerVM.isManualStop ? "Session Ended Early" : "Session Complete")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .italic()

            TrackedLabel(
                text: timerVM.isManualStop ? "Log what you accomplished" : "FocusFlow macOS Experience",
                font: .system(size: 10, weight: .medium),
                color: LiquidDesignTokens.Surface.onSurfaceMuted,
                tracking: 2.0
            )

            HStack(spacing: 10) {
                statCard(
                    label: "Time Elapsed",
                    value: "\(Int((timerVM.lastCompletedDuration ?? 0) / 60))m Session",
                    valueColor: LiquidDesignTokens.Spectral.electricBlue
                )

                statCard(
                    label: "Active Project",
                    value: timerVM.lastCompletedLabel ?? "Focus",
                    valueColor: LiquidDesignTokens.Surface.onSurface
                )
            }
            .accessibilityElement(children: .combine)

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
        }
        .padding(.top, 8)
    }

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

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrackedLabel(
                text: "What Did You Finish?",
                font: .system(size: 11, weight: .semibold),
                tracking: 1.8
            )

            TextField("Log your wins — one per line...", text: $achievement, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.plain)
                .padding(10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))

            if !achievement.isEmpty {
                achievementPreview
            }
        }
    }

    private var achievementPreview: some View {
        let items = achievement.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LiquidDesignTokens.Spectral.mint)
                    Text(item.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
        .animation(FFMotion.control, value: achievement)
    }

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
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

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

    private var focusActionsSection: some View {
        VStack(spacing: 12) {
            // Primary CTA: Take a Break (always shown; label adapts for manual stop)
            GradientCTAButton(
                title: timerVM.isManualStop ? "Save & Take a Break" : "Take a Break",
                icon: "cup.and.saucer.fill",
                gradient: LiquidDesignTokens.Gradient.breakStart
            ) {
                saveAndDismiss(action: .takeBreak)
            }

            GlassEffectContainer {
                VStack(spacing: 8) {
                    // Skip break / Continue
                    HStack(spacing: 8) {
                        Button {
                            saveAndDismiss(action: .continueFocusing)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: timerVM.isManualStop ? "play.fill" : "forward.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(timerVM.isManualStop ? "Save & Keep Going" : "Skip Break")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    }

                    // Continue in overtime (not shown for manual stop — session already ended)
                    if !timerVM.isManualStop {
                        Button {
                            continueOvertimeAndDismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Continue Focusing")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    }

                    // Finish / Save & Done
                    Button {
                        saveAndDismiss(action: .endSession)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text(timerVM.isManualStop ? "Save & Done" : "Finish Session")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .tint(LiquidDesignTokens.Spectral.mint)

                    // Discard — only for manual stops (no reason to discard a naturally-completed session)
                    if timerVM.isManualStop {
                        Button {
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
                    }
                }
            }
        }
    }

    private func continueOvertimeAndDismiss() {
        Task {
            await timerVM.saveReflection(
                mood: selectedMood,
                achievement: achievement.isEmpty ? nil : achievement,
                reminderIdsToComplete: selectedReminderItems.map(\.id),
                splits: showSplits ? splits : nil
            )
            await MainActor.run {
                timerVM.continueAfterCompletion(action: .continueFocusing)
                dismissWindow(id: "session-complete")
            }
        }
    }

    private func saveAndDismiss(action: PostCompletionAction) {
        Task {
            await timerVM.saveReflection(
                mood: selectedMood,
                achievement: achievement.isEmpty ? nil : achievement,
                reminderIdsToComplete: selectedReminderItems.map(\.id),
                splits: showSplits ? splits : nil
            )
            await MainActor.run {
                timerVM.continueAfterCompletion(action: action)
                dismissWindow(id: "session-complete")
            }
        }
    }

    // MARK: - Break Completion

    private var breakContent: some View {
        VStack(spacing: 16) {
            breakHeaderSection
            breakActionsSection
        }
        .padding(18)
        .frame(width: 340)
    }

    private var breakHeaderSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text("Break Complete")
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
        }
        .padding(.top, 8)
    }

    private var breakActionsSection: some View {
        GlassEffectContainer {
            VStack(spacing: 8) {
                LiquidActionButton(
                    title: "Start Focusing",
                    icon: "play.fill",
                    role: .primary,
                    tint: .blue
                ) {
                    timerVM.continueAfterCompletion(action: .continueFocusing)
                    dismissWindow(id: "session-complete")
                }

                LiquidActionButton(
                    title: "End",
                    icon: "stop.fill",
                    role: .secondary
                ) {
                    timerVM.continueAfterCompletion(action: .endSession)
                    dismissWindow(id: "session-complete")
                }
            }
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
                .overlay(Color.black.opacity(0.2))
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

    // MARK: - Helpers

    private func statCard(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TrackedLabel(
                text: label,
                font: .system(size: 10, weight: .semibold),
                tracking: 1.5
            )

            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bringWindowToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Try immediately and with delays to catch the window at different lifecycle stages
        for delay in [0.0, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Find our window — match by content size since hiddenTitleBar may blank the title
                let allWindows = NSApplication.shared.windows
                NSLog("FocusFlow: [delay=\(delay)] window count=\(allWindows.count), titles=\(allWindows.map { $0.title })")
                for window in allWindows {
                    // Match by: not the menu bar panel, not the stats window, has content
                    if window.title == "Session Complete" || window.identifier?.rawValue.contains("session-complete") == true {
                        NSLog("FocusFlow: Found window by title/id: \(window.title)")
                        window.level = .floating
                        window.makeKeyAndOrderFront(nil)
                        window.center()
                        return
                    }
                }
                // Fallback: find the newest non-panel window that isn't the stats window
                if let window = allWindows.last(where: {
                    !$0.title.isEmpty && $0.title != "FocusFlow" && !($0 is NSPanel) && $0.isVisible
                }) {
                    NSLog("FocusFlow: Fallback window: \(window.title) frame=\(window.frame)")
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    window.center()
                }
            }
        }
    }
}
