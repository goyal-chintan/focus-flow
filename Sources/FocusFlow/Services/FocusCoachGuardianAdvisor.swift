import Foundation

struct FocusCoachGuardianRecommendation: Sendable {
    let target: String
    let reason: String
    let confidence: Double
}

enum FocusCoachGuardianState: String, Sendable {
    case observe
    case watchful
    case challenge
    case release
}

/// Derives actionable guardian recommendations from observed app usage.
/// Keeps recommendation logic centralized and testable.
struct FocusCoachGuardianAdvisor: Sendable {
    private static let blockableWebTargets: [String] = [
        "youtube.com",
        "reddit.com",
        "x.com",
        "twitter.com",
        "instagram.com",
        "facebook.com",
        "tiktok.com",
        "netflix.com",
        "twitch.tv"
    ]

    func recommendation(
        frontmostBundleId: String?,
        frontmostAppName: String?,
        entries: [AppUsageEntry],
        selectedProject: Project?
    ) -> FocusCoachGuardianRecommendation? {
        let likelyTarget = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: frontmostBundleId ?? "",
            appName: frontmostAppName ?? ""
        )

        let topRiskEntry = entries
            .filter { entry in
                AppUsageEntry.recommendedBlockTarget(
                    bundleIdentifier: entry.bundleIdentifier,
                    appName: entry.appName
                ) != nil
            }
            .max { riskScore(for: $0) < riskScore(for: $1) }

        let fallbackTarget = topRiskEntry.flatMap {
            AppUsageEntry.recommendedBlockTarget(
                bundleIdentifier: $0.bundleIdentifier,
                appName: $0.appName
            )
        }

        guard let target = likelyTarget ?? fallbackTarget else { return nil }

        if let profile = selectedProject?.blockProfile {
            if target.lowercased().hasPrefix("app:") {
                let bundleTarget = AppUsageEntry.recommendationDisplayLabel(for: target)
                if profile.blockedApps.contains(bundleTarget) {
                    return nil
                }
            } else if profile.blockedWebsites.contains(target) {
                return nil
            }
        }

        let displayTarget = AppUsageEntry.recommendationDisplayLabel(for: target)
        let minutes = max(1, Int((topRiskEntry?.outsideFocusSeconds ?? 0) / 60))
        let reason: String
        if let projectName = selectedProject?.name, !projectName.isEmpty {
            reason = "\(displayTarget) keeps pulling time away from \(projectName) (\(minutes)m today)."
        } else {
            reason = "\(displayTarget) has been a repeated distraction (\(minutes)m today)."
        }
        let confidence = confidenceFor(target: target, source: topRiskEntry)
        return FocusCoachGuardianRecommendation(target: target, reason: reason, confidence: confidence)
    }

    func guardianState(
        isInActiveSession: Bool,
        inReleaseWindow: Bool,
        driftConfidence: Double,
        hasRecommendation: Bool,
        hasRepeatedProjectPattern: Bool = false,
        engagementMode: GuardianEngagementMode = .adaptive
    ) -> FocusCoachGuardianState {
        if inReleaseWindow { return .release }

        // Passive mode: ambient ring signal only, never escalate to challenge
        if engagementMode == .passive { return .observe }

        if isInActiveSession {
            return driftConfidence >= engagementMode.inSessionChallengeThreshold ? .challenge : .watchful
        }

        if driftConfidence >= engagementMode.outsideSessionChallengeThreshold ||
            hasRepeatedProjectPattern ||
           (driftConfidence >= 0.65 && hasRecommendation && engagementMode != .passive) {
            return .challenge
        }
        if driftConfidence >= 0.5 { return .watchful }
        return .observe
    }

    func releaseDuration(for reason: FocusCoachSkipReason?) -> TimeInterval? {
        guard let reason else { return nil }
        switch reason {
        case .doneForToday:
            return 90 * 60
        case .justTired, .notWell:
            return 60 * 60
        case .takingBreak, .inMeeting, .urgentTask:
            return 45 * 60
        case .lowPriorityWork, .procrastinating, .cantFocus:
            return 20 * 60
        }
    }

    private func riskScore(for entry: AppUsageEntry) -> Double {
        let focusWeight = Double(entry.duringFocusSeconds) * 1.5
        let outsideWeight = Double(entry.outsideFocusSeconds)
        return focusWeight + outsideWeight
    }

    private func confidenceFor(target: String, source: AppUsageEntry?) -> Double {
        let base: Double = Self.blockableWebTargets.contains(target) ? 0.85 : 0.65
        guard let source else { return base }
        let seconds = source.duringFocusSeconds + source.outsideFocusSeconds
        if seconds >= 1800 { return min(0.98, base + 0.1) }
        if seconds >= 900 { return min(0.95, base + 0.05) }
        return base
    }
}
