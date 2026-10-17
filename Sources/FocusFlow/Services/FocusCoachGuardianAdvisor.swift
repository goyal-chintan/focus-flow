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

    /// Minimum usage today before a target may be recommended for blocking (Coach v2 design W1).
    static let minimumDailySecondsForBlockRecommendation = 20 * 60

    /// Recommends a block only for a target that is classified as distracting **and** has at
    /// least `minimumDailySecondsForBlockRecommendation` of use today. Work tools and short
    /// visits are never recommended.
    func recommendation(
        frontmostBundleId: String?,
        frontmostAppName: String?,
        entries: [AppUsageEntry],
        selectedProject: Project?
    ) -> FocusCoachGuardianRecommendation? {
        var secondsByTarget: [String: Int] = [:]
        var riskByTarget: [String: Double] = [:]
        // A browser's own app entry is not a precise target; only domain-keyed entries are.
        let candidates = entries.filter {
            !AppUsageEntry.isBrowserBundleIdentifier($0.bundleIdentifier) && Self.isDistracting($0)
        }
        for entry in candidates {
            guard let target = AppUsageEntry.recommendedBlockTarget(
                bundleIdentifier: entry.bundleIdentifier,
                appName: entry.appName
            ) else { continue }
            secondsByTarget[target, default: 0] += entry.duringFocusSeconds + entry.outsideFocusSeconds
            riskByTarget[target, default: 0] += riskScore(for: entry)
        }
        let qualifying = secondsByTarget.filter { $0.value >= Self.minimumDailySecondsForBlockRecommendation }
        guard !qualifying.isEmpty else { return nil }

        let frontmostTarget = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: frontmostBundleId ?? "",
            appName: frontmostAppName ?? ""
        )
        let target: String
        if let frontmostTarget, qualifying[frontmostTarget] != nil {
            target = frontmostTarget
        } else if let top = qualifying.keys.sorted().max(by: { (riskByTarget[$0] ?? 0) < (riskByTarget[$1] ?? 0) }) {
            target = top
        } else {
            return nil
        }

        if let selectedProject {
            if target.lowercased().hasPrefix("app:") {
                let bundleTarget = AppUsageEntry.recommendationDisplayLabel(for: target).lowercased()
                if selectedProject.mergedBlockedApps.contains(bundleTarget) {
                    return nil
                }
            } else if selectedProject.mergedBlockedWebsites.contains(target.lowercased()) {
                return nil
            }
        }

        let displayTarget = AppUsageEntry.recommendationDisplayLabel(for: target)
        let seconds = qualifying[target] ?? 0
        let minutes = seconds / 60
        let reason: String
        if let projectName = selectedProject?.name, !projectName.isEmpty {
            reason = "\(displayTarget) keeps pulling time away from \(projectName) (\(minutes)m today)."
        } else {
            reason = "\(displayTarget) has been a repeated distraction (\(minutes)m today)."
        }
        let confidence = confidenceFor(target: target, totalSeconds: seconds)
        return FocusCoachGuardianRecommendation(target: target, reason: reason, confidence: confidence)
    }

    private static func isDistracting(_ entry: AppUsageEntry) -> Bool {
        AppUsageEntry.classify(
            bundleIdentifier: entry.bundleIdentifier,
            appName: entry.appName,
            browserHost: CompanionAnalyticsBuilder.validPersistedDomainHost(for: entry.bundleIdentifier)
        ) == .distracting
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

    private func confidenceFor(target: String, totalSeconds seconds: Int) -> Double {
        let base: Double = Self.blockableWebTargets.contains(target) ? 0.85 : 0.65
        if seconds >= 1800 { return min(0.98, base + 0.1) }
        if seconds >= 900 { return min(0.95, base + 0.05) }
        return base
    }
}
