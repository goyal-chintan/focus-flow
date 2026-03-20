import AppKit
import Foundation
import SwiftData

/// Tracks app foreground time and sends nudge notifications when the user has FocusFlow
/// open without an active session for too long.
@MainActor
final class AppUsageTracker {
    static let shared = AppUsageTracker()

    private var trackingTimer: Timer?
    private var idleSeconds: Int = 0
    private var isTracking = false
    private var hasNudgedThisIdle = false
    private weak var timerVM: TimerViewModel?

    private init() {}

    // MARK: - Lifecycle

    func start(timerVM: TimerViewModel) {
        guard !isTracking else { return }
        self.timerVM = timerVM
        isTracking = true
        idleSeconds = 0
        hasNudgedThisIdle = false

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(trackingTimer!, forMode: .common)
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

        // Only count idle time when not in a session
        let isIdle = vm.state == .idle && !vm.isOvertime
        if isIdle {
            idleSeconds += 1

            // Check threshold for nudge
            let threshold = vm.settings?.antiProcrastinationThresholdMinutes ?? 5
            let enabled = vm.settings?.antiProcrastinationEnabled ?? true

            if enabled && !hasNudgedThisIdle && idleSeconds >= threshold * 60 {
                sendNudge()
                hasNudgedThisIdle = true
            }
        } else {
            // Reset when user starts a session
            if idleSeconds > 0 {
                idleSeconds = 0
                hasNudgedThisIdle = false
            }
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
