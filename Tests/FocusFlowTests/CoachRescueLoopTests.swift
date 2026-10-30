import XCTest
@testable import FocusFlow

/// Pure parts of the rescue loop: DriftMonitor levels and thresholds, the work-tool rule,
/// the ladder, the momentum ramp, pause-screen guardrails, quotes and 1% framings.
final class CoachRescueLoopTests: XCTestCase {
    private let windowStart = Date(timeIntervalSince1970: 1_800_000_000)
    private var t0: Date { windowStart.addingTimeInterval(60) }

    // MARK: DriftMonitor

    private func monitor(_ samples: [(minute: Int, kind: DriftSampleKind)], rate: Double = 0) -> DriftMonitor {
        var monitor = DriftMonitor()
        for sample in samples {
            monitor.record(at: t0.addingTimeInterval(TimeInterval(sample.minute * 60)), seconds: 60, kind: sample.kind, switchesPerMinute: rate)
        }
        return monitor
    }

    private func context(at minute: Int, ignored: Int = 0, session: Bool = false, inWindow: Bool = true, pressure: Double? = nil, lastEnd: Date? = nil) -> DriftMonitor.Context {
        DriftMonitor.Context(
            now: t0.addingTimeInterval(TimeInterval(minute * 60)),
            sessionActive: session,
            inLearnedWindow: inWindow,
            pacingPressure: pressure,
            windowStart: windowStart,
            lastSessionEnd: lastEnd,
            ignoredRescues: ignored
        )
    }

    private func youtube(_ minutes: Range<Int>) -> [(minute: Int, kind: DriftSampleKind)] {
        minutes.map { ($0, .derailer(name: "YouTube")) }
    }

    func testDerailerThresholdsMoveTheLevelUp() {
        XCTAssertEqual(monitor(youtube(0..<9)).assess(context(at: 9)).level, .ok)
        let l1 = monitor(youtube(0..<10)).assess(context(at: 10))
        XCTAssertEqual(l1.level, .drifting)
        XCTAssertEqual(l1.derailerRecentMinutes, DriftMonitor.derailerMinutesForDrifting)
        XCTAssertEqual(monitor(youtube(0..<19)).assess(context(at: 19)).level, .drifting)
        XCTAssertEqual(monitor(youtube(0..<20)).assess(context(at: 20)).level, .lost)
        XCTAssertEqual(monitor(youtube(0..<39)).assess(context(at: 39)).level, .lost)
        let spiral = monitor(youtube(0..<40)).assess(context(at: 40))
        XCTAssertEqual(spiral.level, .spiral)
        XCTAssertEqual(spiral.derailerWindowMinutes, 40)
        XCTAssertEqual(spiral.topDerailer?.name, "YouTube")
        XCTAssertEqual(spiral.dominantSignal, .derailer(name: "YouTube", minutes: 40))
    }

    func testRecentDerailerTimeIsARolling30MinuteWindowButSpiralCountsTheWholeWindow() {
        // 15 minutes of YouTube, then 30 minutes of work: recent time drops out, window time stays.
        var samples = youtube(0..<15)
        samples += (15..<45).map { ($0, DriftSampleKind.other) }
        let drift = monitor(samples).assess(context(at: 45))
        XCTAssertEqual(drift.derailerRecentMinutes, 0)
        XCTAssertEqual(drift.derailerWindowMinutes, 15)
        XCTAssertEqual(drift.level, .ok)
    }

    func testPseudoWorkThresholdsUseASixtyMinuteLookback() {
        let claude = (0..<40).map { ($0, DriftSampleKind.pseudo(name: "Claude")) }
        XCTAssertEqual(monitor(Array(claude.prefix(19))).assess(context(at: 19)).level, .ok)
        XCTAssertEqual(monitor(Array(claude.prefix(20))).assess(context(at: 20)).level, .drifting)
        let lost = monitor(claude).assess(context(at: 40))
        XCTAssertEqual(lost.level, .lost)
        XCTAssertEqual(lost.pseudoMinutes, 40)
        XCTAssertEqual(lost.dominantSignal, .pseudo(name: "Claude", minutes: 40))
    }

    func testHoppingNeedsSixSwitchesAMinuteSustainedForThreeMinutes() {
        var hopping = DriftMonitor()
        for second in stride(from: 0, through: 180, by: 15) {
            hopping.record(at: t0.addingTimeInterval(TimeInterval(600 + second)), seconds: 15, kind: .other, switchesPerMinute: 7)
        }
        let assessed = hopping.assess(context(at: 13))
        XCTAssertTrue(assessed.isHopping)
        XCTAssertEqual(assessed.level, .drifting)
        XCTAssertEqual(assessed.dominantSignal, .hopping)

        var brief = DriftMonitor()
        for second in stride(from: 0, through: 180, by: 15) {
            brief.record(at: t0.addingTimeInterval(TimeInterval(600 + second)), seconds: 15, kind: .other, switchesPerMinute: second == 90 ? 3 : 8)
        }
        XCTAssertFalse(brief.assess(context(at: 13)).isHopping, "One calm reading breaks the run")

        var short = DriftMonitor()
        for second in stride(from: 0, through: 60, by: 15) {
            short.record(at: t0.addingTimeInterval(TimeInterval(720 + second)), seconds: 15, kind: .other, switchesPerMinute: 9)
        }
        XCTAssertFalse(short.assess(context(at: 13)).isHopping, "Under 3 minutes is not sustained")
    }

    func testIgnoredRescuesRaiseTheLevel() {
        XCTAssertEqual(DriftMonitor.level(base: .drifting, ignoredRescues: 0), .drifting)
        XCTAssertEqual(DriftMonitor.level(base: .drifting, ignoredRescues: 1), .lost)
        XCTAssertEqual(DriftMonitor.level(base: .drifting, ignoredRescues: 2), .spiral)
        XCTAssertEqual(DriftMonitor.level(base: .lost, ignoredRescues: 1), .lost)
        XCTAssertEqual(DriftMonitor.level(base: .lost, ignoredRescues: 2), .spiral)
        XCTAssertEqual(DriftMonitor.level(base: .ok, ignoredRescues: 5), .ok, "Ignores never create drift")
        let drift = monitor(youtube(0..<12)).assess(context(at: 12, ignored: 1))
        XCTAssertEqual(drift.baseLevel, .drifting)
        XCTAssertEqual(drift.level, .lost)
    }

    func testMonitorOnlyRunsWithoutASessionInAWindowOrUnderPacingPressure() {
        let m = monitor(youtube(0..<25))
        XCTAssertFalse(m.assess(context(at: 25, session: true)).isActive)
        XCTAssertFalse(m.assess(context(at: 25, inWindow: false, pressure: 0.3)).isActive)
        XCTAssertFalse(m.assess(context(at: 25, inWindow: false, pressure: nil)).isActive)
        XCTAssertTrue(m.assess(context(at: 25, inWindow: false, pressure: 0.5)).isActive)
        XCTAssertEqual(m.assess(context(at: 25)).level, .lost)
    }

    func testAFocusBlockResetsTheCount() {
        let m = monitor(youtube(0..<25))
        let end = t0.addingTimeInterval(20 * 60)
        let drift = m.assess(context(at: 25, lastEnd: end))
        XCTAssertEqual(drift.derailerWindowMinutes, 4, "Only minutes after the block ended count")
        XCTAssertEqual(drift.level, .ok)
        var reset = m
        reset.reset()
        XCTAssertEqual(reset.assess(context(at: 25)).level, .ok)
    }

    // MARK: Work tools are never derailers

    func testWorkToolsAreNeverDerailers() {
        let workTools: [(bundle: String, name: String, host: String?)] = [
            ("com.tinyspeck.slackmacgap", "Slack", nil),
            ("com.todesktop.230313mzl4w4u92", "Cursor", nil),
            ("com.anthropic.claudefordesktop", "Claude", nil),
            ("company.thebrowser.Browser", "Arc", nil),
            ("com.apple.Safari", "Atlassian", "acme.atlassian.net"),
            ("com.apple.Safari", "GitHub", "github.com"),
        ]
        for tool in workTools {
            for category in [AppUsageEntry.AppCategory.productive, .neutral, .distracting] {
                let kind = DriftMonitor.classify(
                    bundleIdentifier: tool.bundle, appName: tool.name, browserHost: tool.host, displayName: tool.name,
                    category: category, pacingPressure: 0.9
                )
                if case .derailer = kind { XCTFail("\(tool.name) must never be a derailer (category \(category))") }
                XCTAssertEqual(kind, .pseudo(name: tool.name), "\(tool.name) is pseudo-work under pacing pressure")
            }
            let onTrack = DriftMonitor.classify(
                bundleIdentifier: tool.bundle, appName: tool.name, browserHost: tool.host, displayName: tool.name,
                category: .productive, pacingPressure: 0.2
            )
            XCTAssertEqual(onTrack, .other, "\(tool.name) on track is neither derailer nor pseudo-work")
        }
        // Even a user rule cannot turn a work tool into a derailer.
        let ruled = DriftMonitor.classify(
            bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", browserHost: nil, displayName: "Slack",
            category: .distracting, confirmedKeys: ["com.tinyspeck.slackmacgap"], pacingPressure: 0
        )
        XCTAssertEqual(ruled, .other)
    }

    func testStreamingSitesAreDerailers() {
        for (host, name) in [("youtube.com", "YouTube"), ("x.com", "X"), ("netflix.com", "Netflix"), ("zee5.com", "ZEE5")] {
            let kind = DriftMonitor.classify(
                bundleIdentifier: "com.apple.Safari", appName: "Safari", browserHost: host, displayName: name,
                category: .distracting, pacingPressure: nil
            )
            XCTAssertEqual(kind, .derailer(name: name), host)
        }
        let away = DriftMonitor.classify(
            bundleIdentifier: "com.apple.Safari", appName: "Safari", browserHost: "netflix.com", displayName: "Netflix",
            category: .distracting, pacingPressure: nil, userAway: true
        )
        XCTAssertEqual(away, .derailer(name: "Netflix"), "Watching counts even without input")
        XCTAssertEqual(DriftMonitor.classify(bundleIdentifier: nil, appName: nil, browserHost: nil, displayName: nil, category: .neutral, pacingPressure: 1), .other)
    }

    func testKnownBusyworkContextsArePseudoWorkEvenOnTrack() {
        let kind = DriftMonitor.classify(
            bundleIdentifier: "com.anthropic.claudefordesktop", appName: "Claude", browserHost: nil, displayName: "Claude",
            category: .neutral, pacingPressure: 0.1, busyworkContexts: ["claude"]
        )
        XCTAssertEqual(kind, .pseudo(name: "Claude"))
        let away = DriftMonitor.classify(
            bundleIdentifier: "com.anthropic.claudefordesktop", appName: "Claude", browserHost: nil, displayName: "Claude",
            category: .neutral, pacingPressure: 0.9, userAway: true
        )
        XCTAssertEqual(away, .other, "An away user is not doing pseudo-work")
    }

    // MARK: Ladder

    func testLadderAskShrinksWithDrift() {
        let target = CoachStartTarget(minutes: 50, name: "Ship Side App v1")
        XCTAssertNil(CoachRescueLadder.ask(level: .ok, target: target, starterMinutes: 5))
        let l1 = CoachRescueLadder.ask(level: .drifting, target: target, starterMinutes: 5)
        XCTAssertEqual(l1?.title, "Start 50m on Ship Side App v1")
        XCTAssertEqual(l1?.kind, .normal)
        XCTAssertEqual(l1?.minutes, 50)
        let l2 = CoachRescueLadder.ask(level: .lost, target: target, starterMinutes: 5)
        XCTAssertEqual(l2?.title, "Just 10 minutes on Ship Side App v1")
        XCTAssertEqual(l2?.target?.minutes, 10)
        let l3 = CoachRescueLadder.ask(level: .spiral, target: target, starterMinutes: 5)
        XCTAssertEqual(l3?.title, "5 minutes. Plan the next step.")
        XCTAssertEqual(l3?.kind, .starter)
        XCTAssertNil(l3?.target, "A starter block needs no project or priority")
        XCTAssertEqual(CoachRescueLadder.ask(level: .lost, target: CoachStartTarget(minutes: 25, name: nil), starterMinutes: 5)?.title, "Just 10 minutes")
    }

    func testTwoMinuteStarterSettingFlowsIntoEveryRescueString() {
        let l3 = CoachRescueLadder.ask(level: .spiral, target: CoachStartTarget(minutes: 25, name: "X"), starterMinutes: 2)
        XCTAssertEqual(l3?.title, "2 minutes. Plan the next step.")
        XCTAssertEqual(l3?.minutes, 2)
        XCTAssertEqual(CoachStarterBlock.pauseScreenTitle(minutes: 2), "Start 2 minutes")
        XCTAssertEqual(CoachStarterBlock.hotkeyHint(minutes: 2), "⌃⌥Space starts 2 min anytime")
        XCTAssertEqual(CoachStarterBlock.startedNotice(minutes: 2), "Starter block started · 2 min")
        XCTAssertEqual(CoachOnePercent.todayShare(give: 2), "1% of today is 14 minutes. Give 2 now.")
        let screen = CoachPauseScreenPresentation(style: .challenger, headline: nil, fact: nil, starterMinutes: 2, attemptID: nil)
        XCTAssertEqual(screen.primaryTitle, "Start 2 minutes")
        let rescue = CoachRescueContext(level: .spiral, signal: .derailer(name: "YouTube", minutes: 47), spanLabel: "in your 22:00 window", ask: l3!, starterMinutes: 2)
        let message = CoachMessageComposer.compose(CoachComposerInput(style: .challenger, trigger: .rescue(rescue), facts: CoachFacts(), target: CoachStartTarget(minutes: 25)))
        XCTAssertEqual(message.primaryTitle, "2 minutes. Plan the next step.")
        XCTAssertEqual(message.detail, .line("1% of today is 14 minutes. Give 2 now."))
        let gentle = CoachMessageComposer.compose(CoachComposerInput(style: .gentle, trigger: .rescue(rescue), facts: CoachFacts(), target: CoachStartTarget(minutes: 25)))
        XCTAssertEqual(gentle.hook, "Just 2 minutes to plan the next step?")
        for text in [message.hook, message.primaryTitle, message.detail?.text ?? ""] {
            XCTAssertFalse(text.contains("5 min"), text)
        }
    }

    func testRescueMessagesStateOneHonestFact() {
        let ask = CoachRescueLadder.ask(level: .drifting, target: CoachStartTarget(minutes: 50, name: "Ship v1"), starterMinutes: 5)!
        let rescue = CoachRescueContext(level: .drifting, signal: .derailer(name: "YouTube", minutes: 23), spanLabel: "in your 22:00 window", ask: ask, priorityName: "Ship v1")
        let challenger = CoachMessageComposer.compose(CoachComposerInput(style: .challenger, trigger: .rescue(rescue), facts: CoachFacts(), target: CoachStartTarget(minutes: 50, name: "Ship v1")))
        XCTAssertEqual(challenger.hook, "23m on YouTube in your 22:00 window.")
        XCTAssertEqual(challenger.primaryTitle, "Start 50m on Ship v1")
        XCTAssertLessThanOrEqual(challenger.factCount, 1)
        XCTAssertEqual(rescue.longFact, "23 minutes on YouTube in your 22:00 window")

        var late = rescue
        late.lateNight = true
        let night = CoachMessageComposer.compose(CoachComposerInput(style: .challenger, trigger: .rescue(late), facts: CoachFacts(), target: CoachStartTarget(minutes: 50)))
        XCTAssertEqual(night.hook, "One small thing, then sleep.")
        XCTAssertEqual(night.detail, .fact("23m on YouTube in your 22:00 window."))

        var comeback = CoachFacts()
        comeback.daysWithoutBlock = 3
        let worse = CoachMessageComposer.compose(CoachComposerInput(style: .challenger, trigger: .rescue(rescue), facts: comeback, target: CoachStartTarget(minutes: 50)))
        XCTAssertEqual(worse.hook, "You've been 1% worse for 3 days. Today you turn it.")
        XCTAssertLessThanOrEqual(worse.factCount, 1)
    }

    // MARK: Starter, keep going, momentum

    func testKeepGoingCopy() {
        XCTAssertEqual(CoachStarterBlock.keepGoingHook(step: "Sketch onboarding"), "Keep going: 20m on Sketch onboarding?")
        XCTAssertEqual(CoachStarterBlock.keepGoingHook(step: "  "), "Keep going: 20 more minutes?")
        let message = CoachMessageComposer.compose(CoachComposerInput(style: .challenger, trigger: .keepGoing(step: "Sketch onboarding"), facts: CoachFacts(), target: CoachStartTarget(minutes: 20)))
        XCTAssertEqual(message.primaryTitle, "Keep going · 20m")
        XCTAssertTrue(CoachStarterBlock.isStarter(customLabel: "Starter", hasProject: false))
        XCTAssertFalse(CoachStarterBlock.isStarter(customLabel: "Starter", hasProject: true))
    }

    func testMomentumRampOffersOnceAfterFiveMinutesOfAShortRescueBlock() {
        XCTAssertTrue(CoachMomentumRamp.shouldOffer(isRescueStart: true, isStarter: false, elapsedSeconds: 300, totalSeconds: 600, alreadyOffered: false))
        XCTAssertFalse(CoachMomentumRamp.shouldOffer(isRescueStart: true, isStarter: false, elapsedSeconds: 299, totalSeconds: 600, alreadyOffered: false))
        XCTAssertFalse(CoachMomentumRamp.shouldOffer(isRescueStart: true, isStarter: false, elapsedSeconds: 400, totalSeconds: 600, alreadyOffered: true))
        XCTAssertFalse(CoachMomentumRamp.shouldOffer(isRescueStart: false, isStarter: false, elapsedSeconds: 400, totalSeconds: 600, alreadyOffered: false))
        XCTAssertFalse(CoachMomentumRamp.shouldOffer(isRescueStart: true, isStarter: true, elapsedSeconds: 300, totalSeconds: 300, alreadyOffered: false))
        XCTAssertFalse(CoachMomentumRamp.shouldOffer(isRescueStart: true, isStarter: false, elapsedSeconds: 400, totalSeconds: 1500, alreadyOffered: false))
        XCTAssertEqual(CoachMomentumRamp.extensionSeconds(totalSeconds: 600), 900)
    }

    // MARK: Cadence and surfaces

    /// R2 (live, Oct 18): an L1 panel timed out, the ignore raised the level to L2 and a second
    /// panel showed 30 s later. A rise caused only by ignored rescues must wait the full 20 minutes.
    func testIgnoredRescueAloneNeverTriggersAnEarlyDecision() {
        let last = CoachRescueCadence.Decision(level: .drifting, at: windowStart, windowStart: windowStart, baseLevel: .drifting)
        XCTAssertFalse(CoachRescueCadence.shouldDecide(level: .lost, baseLevel: .drifting, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(30)))
        XCTAssertFalse(CoachRescueCadence.shouldDecide(level: .lost, baseLevel: .drifting, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(900)))
        XCTAssertTrue(CoachRescueCadence.shouldDecide(level: .lost, baseLevel: .drifting, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(1200)))
        XCTAssertTrue(CoachRescueCadence.shouldDecide(level: .lost, baseLevel: .lost, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(400)))
    }

    func testCadenceDecidesOnLevelRiseNewWindowOrAfterTwentyMinutes() {
        let last = CoachRescueCadence.Decision(level: .drifting, at: windowStart, windowStart: windowStart)
        XCTAssertFalse(CoachRescueCadence.shouldDecide(level: .ok, windowStart: windowStart, last: nil, now: windowStart))
        XCTAssertTrue(CoachRescueCadence.shouldDecide(level: .drifting, windowStart: windowStart, last: nil, now: windowStart))
        XCTAssertFalse(CoachRescueCadence.shouldDecide(level: .drifting, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(600)))
        // A usage-driven rise decides early, but not within 5 minutes of the last decision.
        XCTAssertFalse(CoachRescueCadence.shouldDecide(level: .lost, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(60)))
        XCTAssertTrue(CoachRescueCadence.shouldDecide(level: .lost, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(301)))
        XCTAssertTrue(CoachRescueCadence.shouldDecide(level: .drifting, windowStart: windowStart, last: last, now: windowStart.addingTimeInterval(1200)))
        XCTAssertTrue(CoachRescueCadence.shouldDecide(level: .drifting, windowStart: windowStart.addingTimeInterval(7200), last: last, now: windowStart.addingTimeInterval(7300)))

        XCTAssertEqual(CoachRescueCadence.candidateSurfaces(level: .drifting, panelEnabled: true, pauseScreenAllowed: true), [.silent, .panel])
        XCTAssertEqual(CoachRescueCadence.candidateSurfaces(level: .spiral, panelEnabled: true, pauseScreenAllowed: true), [.silent, .panel, .strongWindow])
        XCTAssertEqual(CoachRescueCadence.candidateSurfaces(level: .spiral, panelEnabled: true, pauseScreenAllowed: false), [.silent, .panel])
    }

    func testContextKeyCarriesLevelAndSurfaceAndStillParsesLegacyKeys() {
        let base = CoachContextKey(availability: .high, idle: .medium, front: .derailer, hasSessionToday: false)
        let rescue = base.rescue(level: .spiral, surface: .pauseScreen)
        XCTAssertEqual(rescue.rawValue, "avail:high|idle:30-90|front:derailer|today:0|lvl:3|surf:pauseScreen")
        let parsed = CoachContextKey(rawValue: rescue.rawValue)
        XCTAssertEqual(parsed?.driftLevel, .spiral)
        XCTAssertEqual(parsed?.rescueSurface, .pauseScreen)
        let legacy = CoachContextKey(rawValue: base.rawValue)
        XCTAssertNotNil(legacy)
        XCTAssertNil(legacy?.driftLevel)
        XCTAssertEqual(CoachRescueSurface.pauseScreen.coachSurface, .strongWindow)
        XCTAssertEqual(CoachRescueSurface(coachSurface: .silent), .ambient)
    }

    func testBanditKeysEachArmByItsOwnSurface() {
        var model = CoachBanditModel()
        let base = CoachContextKey(availability: .high, idle: .short, front: .derailer, hasSessionToday: false)
        // Pause screens always escaped; panels always worked.
        for _ in 0..<30 {
            for style in CoachStyle.allCases {
                model.record(context: base.rescue(level: .spiral, surface: .pauseScreen).rawValue, arm: CoachArm(surface: .strongWindow, style: style), reward: 0)
                model.record(context: base.rescue(level: .spiral, surface: .panel).rawValue, arm: CoachArm(surface: .panel, style: style), reward: 1.5)
            }
        }
        var rng = SplitMix64(seed: 7)
        var panelWins = 0
        for _ in 0..<50 {
            let arm = CoachBanditPolicy().choose(
                contextFor: { base.rescue(level: .spiral, surface: CoachRescueSurface(coachSurface: $0.surface)).rawValue },
                surfaces: [.silent, .panel, .strongWindow],
                preferredStyle: .challenger,
                model: model,
                using: &rng
            )
            if arm.surface == .panel { panelWins += 1 }
        }
        XCTAssertGreaterThan(panelWins, 35)
    }

    // MARK: Pause screen guardrails

    private func pauseInput(
        now: Date? = nil,
        records: [CoachRescueRecord] = [],
        enabled: Bool = true,
        level: DriftLevel = .spiral,
        configure: (inout CoachGuardrails.Input) -> Void = { _ in }
    ) -> CoachPauseScreenPolicy.Input {
        let now = now ?? windowStart.addingTimeInterval(3600)
        var guardrails = CoachGuardrails.Input(now: now)
        guardrails.quietStartMinute = 0
        guardrails.quietEndMinute = 0
        guardrails.maxPromptsPerDay = 10
        configure(&guardrails)
        return .init(enabled: enabled, level: level, windowStart: windowStart, now: now, records: records, guardrails: guardrails)
    }

    func testPauseScreenGuardrails() {
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput()), .allowed)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput(enabled: false)), .disabledInSettings)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput(level: .lost)), .notSpiral)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput { $0.screenShareActive = true }), .screenShare)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput { $0.calendarBusy = true }), .calendarBusy)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput { $0.releaseActive = true }), .released)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput {
            $0.quietStartMinute = 0
            $0.quietEndMinute = 24 * 60 - 1
        }), .quietHours)
        // A panel 10 minutes ago does not block it: the rescue loop has its own cadence.
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput {
            $0.deliveries = [.init(surface: .panel, deliveredAt: $0.now.addingTimeInterval(-600))]
        }), .allowed)
    }

    func testPauseScreenShowsAtMostOncePerWindowAndThreeTimesAWeek() {
        let now = windowStart.addingTimeInterval(3600)
        let earlierThisWindow = CoachRescueRecord(deliveredAt: windowStart.addingTimeInterval(600), level: .spiral, surface: .pauseScreen, outcome: .improved, reward: 1)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput(records: [earlierThisWindow])), .alreadyShownThisWindow)
        let lastWindow = CoachRescueRecord(deliveredAt: windowStart.addingTimeInterval(-3600), level: .spiral, surface: .pauseScreen, outcome: .improved, reward: 1)
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput(records: [lastWindow])), .allowed)
        let week = (1...3).map { CoachRescueRecord(deliveredAt: now.addingTimeInterval(TimeInterval(-$0 * 86_400)), level: .spiral, surface: .pauseScreen, outcome: .improved, reward: 1) }
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput(records: week)), .weeklyCap)
    }

    func testEscapeRateAboveEightyPercentOverFourteenDaysSwitchesThePauseScreenOff() {
        let now = windowStart.addingTimeInterval(3600)
        func pause(daysAgo: Int, started: Bool) -> CoachRescueRecord {
            CoachRescueRecord(
                deliveredAt: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400 - 3600)),
                level: .spiral, surface: .pauseScreen,
                outcome: started ? .improved : .dismissed, reward: started ? 1 : 0
            )
        }
        let escaped = [8, 9, 10, 11, 12].map { pause(daysAgo: $0, started: false) }
        XCTAssertEqual(CoachPauseScreenPolicy.escapeRate(records: escaped, now: now), 1)
        XCTAssertTrue(CoachPauseScreenPolicy.isAutoDisabled(records: escaped, now: now))
        XCTAssertEqual(CoachPauseScreenPolicy.verdict(pauseInput(records: escaped)), .escapeRateTooHigh)

        let mixed = [8, 9, 10, 11].map { pause(daysAgo: $0, started: false) } + [pause(daysAgo: 12, started: true)]
        XCTAssertEqual(CoachPauseScreenPolicy.escapeRate(records: mixed, now: now) ?? 0, 0.8, accuracy: 0.001)
        XCTAssertFalse(CoachPauseScreenPolicy.isAutoDisabled(records: mixed, now: now), "Exactly 80% is not above 80%")

        XCTAssertNil(CoachPauseScreenPolicy.escapeRate(records: Array(escaped.prefix(3)), now: now), "Too few to judge")
        let old = [15, 16, 17, 18, 19].map { pause(daysAgo: $0, started: false) }
        XCTAssertFalse(CoachPauseScreenPolicy.isAutoDisabled(records: old, now: now), "Older than 14 days ages out")
    }

    // MARK: Ambient counter

    func testMenuBarCounterIsCompact() {
        let watched = monitor(youtube(0..<23)).assess(context(at: 23))
        XCTAssertEqual(CoachDriftCounter.text(for: watched), "YouTube 23m")
        var long = DriftMonitor()
        for minute in 0..<12 { long.record(at: t0.addingTimeInterval(TimeInterval(minute * 60)), seconds: 60, kind: .derailer(name: "Amazon Prime Video"), switchesPerMinute: 0) }
        XCTAssertEqual(CoachDriftCounter.text(for: long.assess(context(at: 12))), "Amazon Pr… 12m")
        let pseudo = monitor((0..<25).map { ($0, DriftSampleKind.pseudo(name: "Claude")) }).assess(context(at: 25))
        XCTAssertEqual(CoachDriftCounter.text(for: pseudo), "Drift 25m")
        XCTAssertNil(CoachDriftCounter.text(for: monitor(youtube(0..<5)).assess(context(at: 5))))
        XCTAssertNil(CoachDriftCounter.text(for: .inactive(windowStart: windowStart)))
    }

    // MARK: Quotes

    func testOnlyVerifiedQuotesWithAttribution() {
        let all = CoachQuoteLibrary.all
        XCTAssertEqual(all.count, 46)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for quote in all where !quote.isHouseLine {
            XCTAssertFalse(quote.author.isEmpty)
            XCTAssertFalse(quote.source.isEmpty)
            XCTAssertFalse(quote.situations.isEmpty)
            XCTAssertTrue(quote.attribution.hasPrefix(quote.author))
        }
        let widely = Set(all.filter(\.isWidelyAttributed).map(\.author))
        XCTAssertEqual(widely, ["Jim Rohn", "Sam Levenson", "Pablo Picasso", "Karen Lamb"])
        XCTAssertEqual(all.first { $0.author == "Marcus Aurelius" }?.source, "Meditations 5.20")
        XCTAssertTrue(all.contains { $0.text == "Never miss twice." })
        XCTAssertTrue(all.contains { $0.text == "Hard choices, easy life. Easy choices, hard life." && $0.author == "Jerzy Gregorek" })
    }

    func testSituationFiltering() {
        for situation in CoachSituation.allCases {
            let quotes = CoachQuoteLibrary.quotes(for: situation, style: .challenger)
            XCTAssertFalse(quotes.isEmpty, "\(situation) has quotes")
            XCTAssertTrue(quotes.allSatisfy { $0.situations.contains(situation) })
        }
        XCTAssertTrue(CoachQuoteLibrary.quotes(for: .comeback, style: .challenger).contains { $0.text == "Never miss twice." })
        XCTAssertFalse(CoachQuoteLibrary.quotes(for: .spiral, style: .challenger).contains { $0.text == "Never miss twice." })
    }

    func testPickerNeverRepeatsWithinThreeDaysAndWeighsWhyLinesLikeQuotes() {
        let now = windowStart
        var rng = SplitMix64(seed: 1)
        let candidates = CoachQuotePicker.candidates(situation: .spiral, whyLines: ["Ship by December"], style: .challenger)
        XCTAssertEqual(candidates.count, CoachQuoteLibrary.quotes(for: .spiral, style: .challenger).count + 1)

        var log: [CoachQuoteShow] = []
        var seen = Set<String>()
        for index in 0..<candidates.count {
            let pick = CoachQuotePicker.pick(situation: .spiral, style: .challenger, whyLines: ["Ship by December"], log: log, rewards: [:], now: now.addingTimeInterval(TimeInterval(index * 3600)), using: &rng)
            let item = try! XCTUnwrap(pick)
            XCTAssertFalse(seen.contains(item.id), "No repeat within 3 days")
            seen.insert(item.id)
            log.append(CoachQuoteShow(itemID: item.id, shownAt: now.addingTimeInterval(TimeInterval(index * 3600)), attemptID: nil))
        }
        XCTAssertTrue(seen.contains("why:ship by december"), "Why lines are arms like quotes")
        // v3: the situation's pool is spent, so the picker falls back to another line for the
        // style that was not shown in the last 24 hours (never one of the spiral lines just shown).
        let afterAll = now.addingTimeInterval(TimeInterval(candidates.count * 3600))
        let fallback = CoachQuotePicker.pick(situation: .spiral, style: .challenger, whyLines: ["Ship by December"], log: log, rewards: [:], now: afterAll, using: &rng)
        XCTAssertNotNil(fallback)
        XCTAssertFalse(seen.contains(fallback?.id ?? ""), "Fallback never repeats a line shown in the last 24 h")
        var everything = log
        for (index, quote) in CoachQuoteLibrary.lines(for: .challenger).enumerated() {
            everything.append(CoachQuoteShow(itemID: "quote:\(quote.id)", shownAt: afterAll.addingTimeInterval(TimeInterval(-(index + 1) * 60)), attemptID: nil))
        }
        XCTAssertNil(CoachQuotePicker.pick(situation: .spiral, style: .challenger, whyLines: ["Ship by December"], log: everything, rewards: [:], now: afterAll, using: &rng),
                     "Every line shown within a day: nothing rather than a repeat")
        XCTAssertNotNil(CoachQuotePicker.pick(situation: .spiral, style: .challenger, whyLines: [], log: log, rewards: [:], now: now.addingTimeInterval(4 * 86_400), using: &rng))
    }

    func testQuotesThatPrecedeStartsRise() {
        let winner = "quote:seneca-short-life"
        let loser = "quote:willink-discipline-freedom"
        var log: [CoachQuoteShow] = []
        var rewards: [UUID: Double] = [:]
        for _ in 0..<20 {
            let a = UUID(), b = UUID()
            log.append(CoachQuoteShow(itemID: winner, shownAt: windowStart.addingTimeInterval(-30 * 86_400), attemptID: a))
            log.append(CoachQuoteShow(itemID: loser, shownAt: windowStart.addingTimeInterval(-30 * 86_400), attemptID: b))
            rewards[a] = 2
            rewards[b] = 0
        }
        let posteriors = CoachQuotePicker.posteriors(log: log, rewards: rewards)
        let w = posteriors[winner]!, l = posteriors[loser]!
        XCTAssertGreaterThan(w.alpha / (w.alpha + w.beta), 0.6)
        XCTAssertLessThan(l.alpha / (l.alpha + l.beta), 0.1)
        var rng = SplitMix64(seed: 3)
        var picks: [String: Int] = [:]
        for _ in 0..<200 {
            if let id = CoachQuotePicker.pick(situation: .spiral, style: .challenger, whyLines: [], log: log, rewards: rewards, now: windowStart, using: &rng)?.id {
                picks[id, default: 0] += 1
            }
        }
        // Many unlearned lines (Dan Koe's questions among them) still get explored, but the proven one leads.
        let winnerPicks = picks[winner, default: 0]
        XCTAssertEqual(picks.max { $0.value < $1.value }?.key, winner, "The proven quote leads")
        XCTAssertGreaterThan(winnerPicks, 5 * picks[loser, default: 0])
    }

    // MARK: 1% framings

    func testOnePercentFramingsUseOnlyRealNumbers() {
        XCTAssertEqual(CoachOnePercent.compounding, "1% better daily = 37× in a year.")
        XCTAssertEqual(Int(pow(1.01, 365)), 37)
        XCTAssertEqual(CoachOnePercent.minutesInOnePercentOfDay, Int(24 * 60 * 0.01))
        XCTAssertEqual(CoachOnePercent.todayShare(give: 5), "1% of today is 14 minutes. Give 5 now.")
        XCTAssertEqual(CoachOnePercent.todayShare(give: 10), "1% of today is 14 minutes. Give 10 now.")
        XCTAssertNil(CoachOnePercent.todayShare(give: 25), "Giving more than 1% would make the line false")
        XCTAssertNil(CoachOnePercent.todayShare(give: 0))
        XCTAssertEqual(CoachOnePercent.worseStreak(days: 4), "You've been 1% worse for 4 days. Today you turn it.")
        XCTAssertNil(CoachOnePercent.worseStreak(days: nil), "Unknown count: no line")
        XCTAssertNil(CoachOnePercent.worseStreak(days: 1))
        XCTAssertNil(CoachOnePercent.worseStreak(days: 0))
        // Rescue copy without a known count never uses the worse-streak line.
        let ask = CoachRescueLadder.ask(level: .drifting, target: CoachStartTarget(minutes: 25, name: nil), starterMinutes: 5)!
        let rescue = CoachRescueContext(level: .drifting, signal: .derailer(name: "X", minutes: 12), spanLabel: "today", ask: ask)
        let message = CoachMessageComposer.compose(CoachComposerInput(style: .challenger, trigger: .rescue(rescue), facts: CoachFacts(), target: CoachStartTarget(minutes: 25)))
        XCTAssertFalse(message.hook.contains("1% worse"))
    }

    func testDaysWithoutBlockCountsRealDays() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: windowStart)
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: today)! }
        XCTAssertEqual(CoachHistoryReader.daysWithoutBlock(daysWithSessions: [day(-4)], today: today, calendar: calendar), 3)
        XCTAssertEqual(CoachHistoryReader.daysWithoutBlock(daysWithSessions: [day(-1)], today: today, calendar: calendar), 0)
        XCTAssertNil(CoachHistoryReader.daysWithoutBlock(daysWithSessions: [], today: today, calendar: calendar))
        XCTAssertNil(CoachHistoryReader.daysWithoutBlock(daysWithSessions: [today], today: today, calendar: calendar))
    }
}
