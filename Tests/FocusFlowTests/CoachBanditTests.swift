import XCTest
import SwiftData
@testable import FocusFlow

final class CoachBanditTests: XCTestCase {
    private let context = "avail:high|idle:30-90|front:work|today:0"
    private let panelChallenger = CoachArm(surface: .panel, style: .challenger)
    private let panelGentle = CoachArm(surface: .panel, style: .gentle)

    // MARK: Context key

    func testContextKeyRoundTrips() {
        let key = CoachContextKey(availability: .high, idle: .init(idleSeconds: 45 * 60), front: .init(category: .productive), hasSessionToday: false)
        XCTAssertEqual(key.rawValue, context)
        XCTAssertEqual(CoachContextKey(rawValue: key.rawValue), key)
        XCTAssertEqual(CoachContextKey.Idle(idleSeconds: 5 * 60), .under10)
        XCTAssertEqual(CoachContextKey.Idle(idleSeconds: 95 * 60), .long)
        XCTAssertEqual(CoachContextKey.Front(category: .distracting), .derailer)
        XCTAssertNil(CoachContextKey(rawValue: "garbage"))
    }

    // MARK: Posterior updates

    func testRewardMapsToFractionalBetaEvidence() {
        var model = CoachBanditModel()
        model.record(context: context, arm: panelChallenger, reward: 1)      // start
        model.record(context: context, arm: panelChallenger, reward: 2)      // start + done + shipped
        model.record(context: context, arm: panelChallenger, reward: 0)      // ignored
        model.record(context: context, arm: panelChallenger, reward: -0.5)   // clamps to 0

        let evidence = model.evidence(context: context, arm: panelChallenger)
        XCTAssertEqual(evidence.successes, 1.5, accuracy: 1e-9)
        XCTAssertEqual(evidence.failures, 2.5, accuracy: 1e-9)
        XCTAssertEqual(evidence.pulls, 4)
    }

    func testPriorRespectsChosenStyleAndSilentIsFixedSmall() {
        XCTAssertEqual(CoachBanditPolicy.prior(for: panelChallenger, preferredStyle: .challenger).alpha, 3)
        XCTAssertEqual(CoachBanditPolicy.prior(for: panelChallenger, preferredStyle: .challenger).beta, 1)
        XCTAssertEqual(CoachBanditPolicy.prior(for: panelGentle, preferredStyle: .challenger).alpha, 1)
        XCTAssertEqual(CoachBanditPolicy.prior(for: panelGentle, preferredStyle: .challenger).beta, 1)
        let silent = CoachBanditPolicy.prior(for: .silent, preferredStyle: .challenger)
        XCTAssertEqual(silent.alpha / (silent.alpha + silent.beta), 0.05, accuracy: 1e-9)

        var model = CoachBanditModel()
        model.record(context: context, arm: .silent, reward: 2)
        XCTAssertEqual(model.evidence(context: context, arm: .silent).pulls, 0, "Silent never learns")
    }

    func testPosteriorAddsLocalEvidenceAndPoolsOtherContexts() {
        var model = CoachBanditModel()
        model.record(context: context, arm: panelChallenger, reward: 2)
        model.record(context: "avail:medium|idle:10-30|front:neutral|today:1+", arm: panelChallenger, reward: 0)

        let posterior = CoachBanditPolicy.posterior(for: panelChallenger, context: context, model: model, preferredStyle: .challenger)
        XCTAssertEqual(posterior.alpha, 3 + 1, accuracy: 1e-9)
        XCTAssertEqual(posterior.beta, 1 + 0 + CoachBanditModel.globalPoolingWeight * 1, accuracy: 1e-9)
    }

    func testRebuildFromRecordsMatchesIncrementalUpdates() {
        let records = [
            CoachRewardRecord(contextKey: context, arm: panelChallenger, reward: 1),
            CoachRewardRecord(contextKey: context, arm: panelGentle, reward: 0),
            CoachRewardRecord(contextKey: context, arm: panelChallenger, reward: 1.5),
        ]
        var incremental = CoachBanditModel()
        records.forEach { incremental.record(context: $0.contextKey, arm: $0.arm, reward: $0.reward) }
        XCTAssertEqual(CoachBanditModel.rebuild(from: records), incremental)
    }

    func testRewardRecordReadsLearningFieldsFromAttempt() {
        let attempt = InterventionAttempt(kind: .strongPrompt, riskScore: 0.1)
        XCTAssertNil(CoachRewardRecord(attempt: attempt), "Rows without a context key are not bandit decisions")
        attempt.surfaceRawValue = CoachSurface.panel.rawValue
        attempt.styleRawValue = CoachStyle.data.rawValue
        attempt.contextKey = context
        XCTAssertNil(CoachRewardRecord(attempt: attempt), "Unresolved rows are skipped")
        attempt.reward = 1.5
        XCTAssertEqual(CoachRewardRecord(attempt: attempt), CoachRewardRecord(contextKey: context, arm: CoachArm(surface: .panel, style: .data), reward: 1.5))
    }

    // MARK: Arm selection

    func testSelectionIsDeterministicForASeed() {
        let policy = CoachBanditPolicy()
        func run(seed: UInt64) -> [CoachArm] {
            var rng = SplitMix64(seed: seed)
            return (0..<25).map { _ in
                policy.choose(context: context, surfaces: [.silent, .badge, .panel], preferredStyle: .challenger, model: CoachBanditModel(), using: &rng)
            }
        }
        XCTAssertEqual(run(seed: 42), run(seed: 42))
        XCTAssertNotEqual(run(seed: 42), run(seed: 43))
    }

    func testColdStartFavoursChosenStyleOnThePanel() {
        let policy = CoachBanditPolicy()
        var rng = SplitMix64(seed: 2026)
        var counts: [CoachArm: Int] = [:]
        for _ in 0..<500 {
            let arm = policy.choose(context: context, surfaces: [.silent, .badge, .panel], preferredStyle: .challenger, model: CoachBanditModel(), using: &rng)
            counts[arm, default: 0] += 1
        }
        let top = counts.max { $0.value < $1.value }?.key
        XCTAssertEqual(top, panelChallenger)
        XCTAssertLessThan(counts[.silent, default: 0], 25)
    }

    func testCoachGoesQuietWhenNothingWorks() {
        var model = CoachBanditModel()
        for arm in CoachArm.arms(for: [.badge, .panel]) {
            for _ in 0..<150 { model.record(context: context, arm: arm, reward: 0) }
        }
        let policy = CoachBanditPolicy()
        var rng = SplitMix64(seed: 9)
        let silent = (0..<300).filter { _ in
            policy.choose(context: context, surfaces: [.silent, .badge, .panel], preferredStyle: .challenger, model: model, using: &rng) == .silent
        }.count
        XCTAssertGreaterThan(silent, 150, "At ~0% response the silent arm should win most draws")
    }

    func testLearnsThatAnotherStyleWorksBetter() {
        var model = CoachBanditModel()
        for _ in 0..<40 {
            model.record(context: context, arm: panelChallenger, reward: 0)
            model.record(context: context, arm: panelGentle, reward: 1.5)
        }
        let policy = CoachBanditPolicy()
        var rng = SplitMix64(seed: 11)
        let picks = (0..<200).map { _ in
            policy.choose(context: context, surfaces: [.panel], preferredStyle: .challenger, model: model, using: &rng)
        }
        // The untried Data arm (Beta(1,1)) still gets explored; Challenger's stated preference loses to the data.
        XCTAssertGreaterThan(picks.filter { $0 == panelGentle }.count, 120)
        XCTAssertLessThan(picks.filter { $0 == panelChallenger }.count, 10)
    }

    func testNeverChoosesASurfaceThatWasNotOffered() {
        let policy = CoachBanditPolicy()
        var rng = SplitMix64(seed: 5)
        for _ in 0..<200 {
            let arm = policy.choose(context: context, surfaces: [.silent, .badge], preferredStyle: .data, model: CoachBanditModel(), using: &rng)
            XCTAssertTrue(arm.surface == .badge || arm.surface == .silent)
        }
    }

    func testBetaSamplerMeanIsClose() {
        var rng = SplitMix64(seed: 1)
        let samples = (0..<4000).map { _ in BetaSampler.sample(alpha: 3, beta: 1, using: &rng) }
        XCTAssertEqual(samples.reduce(0, +) / Double(samples.count), 0.75, accuracy: 0.02)
        let small = (0..<4000).map { _ in BetaSampler.sample(alpha: 0.5, beta: 0.5, using: &rng) }
        XCTAssertEqual(small.reduce(0, +) / Double(small.count), 0.5, accuracy: 0.03)
    }

    // MARK: Persistence

    func testStoreRoundTripsThroughUserDefaults() throws {
        let suite = "CoachBanditTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var model = CoachBanditModel()
        model.record(context: context, arm: panelChallenger, reward: 1)
        let store = CoachBanditStore(defaults: defaults)
        XCTAssertNil(store.load())
        store.save(model)
        XCTAssertEqual(store.load(), model)
    }

    // MARK: Guardrails

    func testQuietHoursWrapPastMidnight() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let at = { (h: Int, m: Int) in calendar.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        XCTAssertTrue(CoachGuardrails.isQuietHours(at(0, 45), start: 30, end: 420))
        XCTAssertFalse(CoachGuardrails.isQuietHours(at(22, 30), start: 30, end: 420))
        XCTAssertTrue(CoachGuardrails.isQuietHours(at(23, 30), start: 23 * 60, end: 7 * 60))
        XCTAssertTrue(CoachGuardrails.isQuietHours(at(3, 0), start: 23 * 60, end: 7 * 60))
        XCTAssertFalse(CoachGuardrails.isQuietHours(at(12, 0), start: 23 * 60, end: 7 * 60))
        XCTAssertFalse(CoachGuardrails.isQuietHours(at(3, 0), start: 0, end: 0), "Equal start and end disables quiet hours")
    }

    func testHardGuardrailsBlockEverySurfaceButSilent() {
        let guardrails = CoachGuardrails()
        let now = Date()
        func input(_ edit: (inout CoachGuardrails.Input) -> Void) -> CoachGuardrails.Input {
            var input = CoachGuardrails.Input(now: now, quietStartMinute: 0, quietEndMinute: 0)
            edit(&input)
            return input
        }
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input { $0.calendarBusy = true }), .calendarBusy)
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input { $0.screenShareActive = true }), .screenShare)
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input { $0.releaseActive = true }), .released)
        XCTAssertEqual(guardrails.verdict(for: .badge, input: input { $0.snoozedUntil = now.addingTimeInterval(60) }), .snoozed)
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input { $0.sessionActive = true }), .sessionActive)
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input {
            $0.sessionActive = true
            $0.isIdlePrompt = false
        }), .allowed, "The in-session drift check may show during a session")
        XCTAssertEqual(guardrails.verdict(for: .silent, input: input { $0.calendarBusy = true }), .allowed)
        XCTAssertEqual(guardrails.verdict(for: .badge, input: input {
            $0.maxPromptsPerDay = 1
            $0.deliveries = [.init(surface: .badge, deliveredAt: now.addingTimeInterval(-60))]
        }), .dailyCapReached)
    }

    func testAllowedSurfacesDropsPanelWithinTwoHours() {
        let now = Date()
        let input = CoachGuardrails.Input(
            now: now,
            deliveries: [.init(surface: .panel, deliveredAt: now.addingTimeInterval(-3600))],
            quietStartMinute: 0,
            quietEndMinute: 0
        )
        let result = CoachGuardrails().allowedSurfaces(from: [.silent, .badge, .panel], input: input)
        XCTAssertEqual(result.surfaces, [.silent, .badge])
        XCTAssertEqual(result.firstBlock, .panelTooSoon)
    }
}
