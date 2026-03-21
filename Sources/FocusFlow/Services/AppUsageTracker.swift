import AppKit
import Foundation
import SwiftData

/// Tracks app foreground time, records per-app usage, and sends nudge notifications.
@MainActor
final class AppUsageTracker {
    static let shared = AppUsageTracker()

    private var trackingTimer: Timer?
    private var idleSeconds: Int = 0
    private var isTracking = false
    private var hasNudgedThisIdle = false
    private weak var timerVM: TimerViewModel?
    private var modelContext: ModelContext?
    private var tickCount: Int = 0

    // Per-app tracking state
    private var currentAppBundleId: String = ""
    private var currentAppName: String = ""

    private init() {}

    // MARK: - Lifecycle

    func start(timerVM: TimerViewModel, modelContext: ModelContext) {
        trackingTimer?.invalidate()
        self.timerVM = timerVM
        self.modelContext = modelContext
        isTracking = true
        idleSeconds = 0
        hasNudgedThisIdle = false
        tickCount = 0

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let timer = trackingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        log("Started tracking")
    }

    func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        isTracking = false
        idleSeconds = 0
        hasNudgedThisIdle = false
        log("Stopped tracking")
    }

    // MARK: - Tick

    private func tick() {
        guard let vm = timerVM else { return }

        tickCount += 1
        trackFrontmostApp(isFocusing: vm.state == .focusing)

        // Only count idle time when not in a session
        let isIdle = vm.state == .idle && !vm.isOvertime
        if isIdle {
            idleSeconds += 1

            let threshold = vm.settings?.antiProcrastinationThresholdMinutes ?? 5
            let enabled = vm.settings?.antiProcrastinationEnabled ?? true

            if enabled && !hasNudgedThisIdle && idleSeconds >= threshold * 60 {
                sendNudge()
                hasNudgedThisIdle = true
            }
        } else {
            if idleSeconds > 0 {
                idleSeconds = 0
                hasNudgedThisIdle = false
            }
        }
    }

    // MARK: - App Tracking

    private func trackFrontmostApp(isFocusing: Bool) {
        guard let ctx = modelContext else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = frontApp.bundleIdentifier ?? "unknown"
        let appName = frontApp.localizedName ?? "Unknown"

        // Skip FocusFlow itself
        if bundleId == Bundle.main.bundleIdentifier { return }

        let today = Calendar.current.startOfDay(for: Date())

        // Find or create entry for this app + today
        let descriptor = FetchDescriptor<AppUsageEntry>(
            predicate: #Predicate { entry in
                entry.date == today && entry.bundleIdentifier == bundleId
            }
        )

        do {
            let existing = try ctx.fetch(descriptor)
            if let entry = existing.first {
                if isFocusing {
                    entry.duringFocusSeconds += 1
                } else {
                    entry.outsideFocusSeconds += 1
                }
            } else {
                let entry = AppUsageEntry(
                    date: today,
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duringFocusSeconds: isFocusing ? 1 : 0,
                    outsideFocusSeconds: isFocusing ? 0 : 1
                )
                ctx.insert(entry)
            }

            // Save periodically (every 30 seconds) to avoid constant writes
            if tickCount % 30 == 0 {
                try ctx.save()
            }
        } catch {
            log("Failed to track app usage: \(error)")
        }
    }

    // MARK: - Nudge

    private func sendNudge() {
        let messages = [
            "You've been browsing for a while. Ready to start a focus session?",
            "Time flies! How about a quick focus sprint?",
            "Your best ideas happen during deep work. Start a session?",
            "A 25-minute focus session can make all the difference.",
            "Take the first step — start a short focus session."
        ]
        let message = messages.randomElement() ?? messages[0]

        NotificationService.shared.sendGenericNotification(
            title: "Focus Nudge 💡",
            body: message,
            sound: "Tink"
        )
        log("Sent nudge notification after \(idleSeconds)s idle")
    }

    // MARK: - Logging

    private func log(_ message: String) {
        #if DEBUG
        print("[AppUsageTracker] \(message)")
        #endif
    }
}
