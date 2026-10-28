import Foundation

/// Writes bandit rewards onto `InterventionAttempt` rows (Coach v2 design §3 [3], §9).
///
/// Reward per prompt: +1 when a session starts ≤ 10 min after it, +0.5 when that session
/// completes, ± `SessionOutcome.reward` when the user rates it. Silence or "Not now" = 0.
/// Attempts are always resolved by id (never `.first` / `.last`; audit bug B3).
@MainActor
struct CoachRewardLedger {
    static let startWindow: TimeInterval = 10 * 60
    static let startReward = 1.0
    static let completionReward = 0.5

    let store: FocusCoachPersisting

    func attempt(id: UUID) -> InterventionAttempt? {
        store.attempt(id: id)
    }

    /// Credits a session start to the prompt that asked for it. Returns false when the prompt
    /// is unknown, older than 10 minutes, or already credited.
    @discardableResult
    func creditStart(attemptID: UUID, sessionID: UUID, at now: Date = Date()) -> Bool {
        guard let attempt = attempt(id: attemptID),
              attempt.contextKey != nil,
              now.timeIntervalSince(attempt.deliveredAt) <= Self.startWindow,
              (attempt.reward ?? 0) <= 0 else { return false }
        attempt.reward = Self.startReward
        attempt.sessionId = sessionID
        if attempt.outcome == nil || attempt.outcome == .ignored || attempt.outcome == .unseen {
            attempt.outcome = .improved
            attempt.resolvedAt = now
        }
        store.saveChanges()
        return true
    }

    /// Credits a start to the most recent prompt the user saw in the last 10 minutes, whatever
    /// surface started the block (Coach v4 §3.1). The plan card's starts were made from the
    /// popover a minute later and, before v4, were never credited.
    @discardableResult
    func creditLatestSeen(sessionID: UUID, at now: Date = Date()) -> UUID? {
        let candidates = store.attempts(deliveredSince: now.addingTimeInterval(-Self.startWindow)).map {
            CoachPromptAttribution.Candidate(
                id: $0.id,
                deliveredAt: $0.deliveredAt,
                surface: $0.surfaceRawValue.flatMap(CoachSurface.init(rawValue:)),
                outcome: $0.outcome,
                reward: $0.reward,
                hasContext: $0.contextKey != nil
            )
        }
        guard let id = CoachPromptAttribution.creditTarget(for: now, candidates: candidates),
              creditStart(attemptID: id, sessionID: sessionID, at: now) else { return nil }
        return id
    }

    /// Adds the completion bonus to the prompt that led to `sessionID`.
    @discardableResult
    func creditCompletion(sessionID: UUID) -> Bool {
        guard let attempt = learningAttempt(forSession: sessionID), let reward = attempt.reward, reward >= Self.startReward,
              reward < Self.startReward + Self.completionReward else { return false }
        attempt.reward = reward + Self.completionReward
        store.saveChanges()
        return true
    }

    /// Applies the user's rating. Re-rating replaces the previous rating's contribution.
    @discardableResult
    func creditOutcome(sessionID: UUID, outcome: SessionOutcome, previous: SessionOutcome?) -> Bool {
        guard let attempt = learningAttempt(forSession: sessionID), let reward = attempt.reward else { return false }
        attempt.reward = reward - (previous?.reward ?? 0) + outcome.reward
        store.saveChanges()
        return true
    }

    /// Resolves prompts nobody acted on within 10 minutes as reward 0 ("ignored").
    @discardableResult
    func resolveExpired(now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-Self.startWindow)
        var resolved = 0
        for attempt in store.attempts(deliveredSince: now.addingTimeInterval(-7 * 24 * 3600))
        where attempt.contextKey != nil && attempt.reward == nil && attempt.deliveredAt < cutoff
            && attempt.outcome != .unseen {
            attempt.reward = 0
            if attempt.outcome == nil {
                attempt.outcome = .ignored
                attempt.resolvedAt = now
            }
            resolved += 1
        }
        if resolved > 0 { store.saveChanges() }
        return resolved
    }

    /// All resolved learning rows, for rebuilding the bandit.
    func rewardRecords() -> [CoachRewardRecord] {
        store.attempts.compactMap(CoachRewardRecord.init(attempt:))
    }

    private func learningAttempt(forSession sessionID: UUID) -> InterventionAttempt? {
        store.attempts
            .filter { $0.sessionId == sessionID && $0.contextKey != nil }
            .max { $0.deliveredAt < $1.deliveredAt }
    }
}
