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
    private var nudgeCount: Int = 0
    private weak var timerVM: TimerViewModel?
    private var modelContext: ModelContext?
    private var tickCount: Int = 0

    // Per-app tracking state
    private var currentAppBundleId: String = ""
    private var currentAppName: String = ""

    private init() {}

    // MARK: - Lifecycle

    func start(timerVM: TimerViewModel, modelContext: ModelContext) {
        guard !isTracking else { return }
        trackingTimer?.invalidate()
        self.timerVM = timerVM
        self.modelContext = modelContext
        isTracking = true
        idleSeconds = 0
        nudgeCount = 0
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
        nudgeCount = 0
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

            if enabled {
                let nextNudgeSeconds = nudgeInterval(for: nudgeCount, baseMinutes: threshold)
                if idleSeconds >= nextNudgeSeconds {
                    sendNudge(escalationLevel: nudgeCount)
                    nudgeCount += 1
                }
            }
        } else {
            if idleSeconds > 0 {
                idleSeconds = 0
                nudgeCount = 0
            }
        }
    }

    /// Returns the idle seconds threshold for the Nth nudge.
    /// First nudge at base threshold, then escalating: base, base+5min, base+15min, then every 15min.
    private func nudgeInterval(for count: Int, baseMinutes: Int) -> Int {
        switch count {
        case 0: return baseMinutes * 60
        case 1: return (baseMinutes + 5) * 60
        case 2: return (baseMinutes + 15) * 60
        default: return (baseMinutes + 15 + (count - 2) * 15) * 60
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

    private func sendNudge(escalationLevel: Int) {
        guard NotificationService.shared.isAuthorized else {
            log("Notifications not authorized — nudge suppressed")
            return
        }

        let message: String
        switch escalationLevel {
        case 0:
            let gentle = [
                "You've been browsing for a while. Ready to start a focus session?",
                "Time flies! How about a quick focus sprint?",
                "Your best ideas happen during deep work. Start a session?",
            ]
            message = gentle.randomElement() ?? gentle[0]
        case 1:
            let moderate = [
                "Still no focus session started. Even 15 minutes of deep work makes a difference.",
                "Your focus streak is waiting — start a short session to keep momentum.",
                "A quick focus sprint now could turn your day around.",
            ]
            message = moderate.randomElement() ?? moderate[0]
        default:
            let urgent = [
                "You've been idle for a while now. Start a session — you'll thank yourself later.",
                "Deep work doesn't happen by accident. Take the first step — start focusing.",
                "Every productive day starts with one focus session. Ready?",
            ]
            message = urgent.randomElement() ?? urgent[0]
        }

        NotificationService.shared.sendGenericNotification(
            title: escalationLevel == 0 ? "Focus Nudge 💡" : "Focus Reminder 🔔",
            body: message,
            sound: escalationLevel >= 2 ? "Bottle" : "Tink"
        )
        log("Sent nudge #\(escalationLevel + 1) after \(idleSeconds)s idle")
    }

    // MARK: - Logging

    private func log(_ message: String) {
        #if DEBUG
        print("[AppUsageTracker] \(message)")
        #endif
    }
}
