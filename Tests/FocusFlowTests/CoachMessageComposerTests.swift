import XCTest
@testable import FocusFlow

final class CoachMessageComposerTests: XCTestCase {
    private func compose(
        _ style: CoachStyle,
        trigger: CoachTrigger = .startNudge,
        facts: CoachFacts = CoachFacts(),
        target: CoachStartTarget = CoachStartTarget(minutes: 25, name: "FocusFlow"),
        why: [String] = [],
        seed: Int = 0
    ) -> CoachComposedMessage {
        CoachMessageComposer.compose(CoachComposerInput(
            style: style,
            trigger: trigger,
            facts: facts,
            target: target,
            whyLines: why,
            seed: seed
        ))
    }

    // MARK: Structure

    func testMessageIsHookPlusAtMostOneFactPlusOneAction() {
        let message = compose(.challenger, facts: richFacts())
        XCTAssertFalse(message.hook.isEmpty)
        XCTAssertLessThanOrEqual(message.factCount, 1)
        XCTAssertEqual(message.primaryTitle, "Start 25m on FocusFlow")
    }

    func testPrimaryActionNamesMinutesAndTarget() {
        XCTAssertEqual(compose(.data, target: CoachStartTarget(minutes: 50, name: "Ship Side App v1 onboarding flow")).primaryTitle,
                       "Start 50m on Ship Side App v1 onboar…")
        XCTAssertEqual(compose(.data, target: CoachStartTarget(minutes: 35, name: nil)).primaryTitle, "Start 35m focus")
    }

    // MARK: Styles

    func testStylesProduceDifferentVoices() {
        var facts = CoachFacts()
        facts.hasHistory = true
        facts.streakDays = 5
        facts.goalMinutes = 120
        facts.doneMinutesToday = 0

        let challenger = compose(.challenger, facts: facts)
        let data = compose(.data, facts: facts)
        let gentle = compose(.gentle, facts: facts)

        XCTAssertEqual(challenger.hook, "Day 6. Show up.")
        XCTAssertEqual(data.hook, "0m of 120m today.")
        XCTAssertEqual(gentle.hook, "Ready for FocusFlow?")
        XCTAssertEqual(Set([challenger.hook, data.hook, gentle.hook]).count, 3)
    }

    func testChallengerTemplatesFromTheSpec() {
        var facts = CoachFacts()
        facts.goalMinutes = 120
        facts.derailer = CoachDerailerFact(name: "YouTube", minutesThisWeek: 130)
        XCTAssertEqual(compose(.challenger, facts: facts).hook, "YouTube has had 2h 10m of you this week.")

        facts.derailer = nil
        facts.doneMinutesToday = 60
        facts.pacing = CoachGoalPacing(goalMinutes: 120, doneMinutes: 60, windowMinutesLeft: 45)
        XCTAssertEqual(compose(.challenger, facts: facts).hook, "50% of today's goal. 45m of good window left today.")

        facts.pacing = nil
        facts.hasHistory = true
        facts.missedYesterday = true
        XCTAssertEqual(compose(.challenger, facts: facts).hook, "Never miss twice.")

        facts.missedYesterday = false
        facts.sessionsToday = 1
        facts.lastIntent = "Onboarding empty states"
        XCTAssertEqual(compose(.challenger, facts: facts).hook, "You said: “Onboarding empty states”.")

        facts.lastIntent = nil
        // On the way to today's goal: the distance to it, not a generic line (goal gradient).
        XCTAssertTrue(compose(.challenger, facts: facts, seed: 0).hook.hasPrefix("60 of 120 min today."))
        facts.doneMinutesToday = 10
        XCTAssertEqual(compose(.challenger, facts: facts, seed: 0).hook, "1% better daily = 37× in a year.")
    }

    func testDerailerNamedOnlyWhenConfirmed() {
        var facts = CoachFacts()
        facts.goalMinutes = 120
        let message = compose(.challenger, facts: facts)
        XCTAssertFalse(message.accessibilityText.contains("YouTube"))
        XCTAssertFalse(message.accessibilityText.contains("this week"))
        XCTAssertFalse(compose(.gentle, facts: { var f = facts; f.derailer = .init(name: "YouTube", minutesThisWeek: 90); return f }()).accessibilityText.contains("YouTube"),
                       "Gentle never brings up derailers")
    }

    // MARK: Honesty

    func testNeverInventsNumbers() {
        let styles = CoachStyle.allCases
        let triggers: [CoachTrigger] = [
            .startNudge,
            .pseudoProductivity(priority: "Ship v1"),
            .inSessionDrift(projectName: "Side App", appName: "Claude", minutesInApp: 12),
            .inSessionDrift(projectName: nil, appName: nil, minutesInApp: nil),
            .weeklyPriorities,
        ]
        let factSets: [CoachFacts] = [CoachFacts(), richFacts(), sparseFacts()]
        for style in styles {
            for trigger in triggers {
                for facts in factSets {
                    for seed in 0..<4 {
                        let target = CoachStartTarget(minutes: 35, name: "Side App")
                        let message = compose(style, trigger: trigger, facts: facts, target: target, seed: seed)
                        let allowed = allowedNumbers(facts: facts, target: target, trigger: trigger)
                        let text = [message.hook, message.detail?.text ?? "", message.primaryTitle].joined(separator: " ")
                        for number in numbers(in: text) {
                            XCTAssertTrue(allowed.contains(number), "\(style) \(trigger): '\(number)' is not from the data in \"\(text)\"")
                        }
                        XCTAssertLessThanOrEqual(message.factCount, 1, text)
                    }
                }
            }
        }
    }

    func testNeverShames() {
        let banned = ["lazy", "waste", "wasting", "failure", "pathetic", "ashamed", "loser", "excuse"]
        for style in CoachStyle.allCases {
            for facts in [CoachFacts(), richFacts(), sparseFacts()] {
                for trigger in [CoachTrigger.startNudge, .pseudoProductivity(priority: "X"), .weeklyPriorities] {
                    let text = compose(style, trigger: trigger, facts: facts).accessibilityText.lowercased()
                    for word in banned {
                        XCTAssertFalse(text.contains(word), "'\(word)' in \(text)")
                    }
                }
            }
        }
    }

    func testSinceLastBlockUsesRealSessionEnd() {
        var facts = CoachFacts()
        facts.goalMinutes = 120
        facts.hasHistory = true
        facts.missedYesterday = true
        XCTAssertNil(compose(.challenger, facts: facts).detail.flatMap { $0.text.contains("Last block") ? $0 : nil })
        facts.minutesSinceLastSession = 190
        XCTAssertEqual(compose(.challenger, facts: facts).detail, .fact("Last block ended 3h 10m ago."))
    }

    // MARK: Quotes and "My why"

    func testQuoteLibraryIsSeededOnlyWithAttributedSpecQuotes() {
        let all = CoachQuoteLibrary.all
        XCTAssertEqual(all.count, 46, "The rescue loop design §4 seed list, the approved quotes, Challenger house lines and Dan Koe's lines and questions")
        XCTAssertTrue(all.allSatisfy { !$0.situations.isEmpty })
        XCTAssertTrue(all.filter { !$0.isHouseLine }.allSatisfy { !$0.source.isEmpty && !$0.author.isEmpty })
        XCTAssertEqual(all.filter { $0.author == "James Clear" }.count, 5)
        XCTAssertTrue(all.filter { $0.author == "James Clear" }.allSatisfy { $0.source.contains("Atomic Habits") })
        let willink = all.first { $0.author == "Jocko Willink" }
        XCTAssertEqual(willink?.text, "Discipline equals freedom.")
        XCTAssertTrue(willink?.source.contains("Discipline Equals Freedom") == true)
        let durant = all.first { $0.text.hasPrefix("We are what we repeatedly do") }
        XCTAssertEqual(durant?.author, "Will Durant", "Commonly misattributed to Aristotle")
        XCTAssertFalse(all.contains { $0.author.contains("Aristotle") })
    }

    func testOnlySourcedQuotesRotate() {
        XCTAssertEqual(CoachQuoteLibrary.rotation, CoachQuoteLibrary.all)
        XCTAssertTrue(CoachQuoteLibrary.rotation.allSatisfy { $0.isHouseLine || !$0.source.isEmpty })
    }

    func testLibraryContainsOnlyTheApprovedEntries() {
        let expected: Set<String> = [
            // Rescue loop design §4 seed list
            "clear-systems", "clear-vote", "clear-never-miss-twice", "willink-discipline-freedom",
            "durant-excellence-habit", "king-amateurs", "dillard-days", "seneca-short-life",
            "aurelius-obstacle", "rubin-every-day", "gregorek-hard-choices", "rohn-motivation-habit",
            "rohn-discipline-bridge", "levenson-clock", "picasso-inspiration",
            // Approved quotes
            "karen-lamb-year-from-now", "emmett-dread", "seneca-nothing-ours", "seneca-each-day-a-life",
            "aurelius-ten-thousand-years", "franklin-lost-time", "clear-trajectory", "clear-compound-interest",
            "newport-clarity",
            // Challenger house lines
            "house-intelligence-discipline", "house-cost-of-procrastination", "house-give-it-minutes",
            "house-secret-getting-started",
            // Dan Koe, "How to fix your entire life in 1 day" (2025): statements and interrupt questions
            "koe-not-the-person", "koe-afraid", "koe-learn-from-mistakes", "koe-progress", "koe-anti-vision-stakes",
            "koe-levers-quests", "koe-q-avoiding", "koe-q-filmed", "koe-q-toward", "koe-q-pretending",
            "koe-q-identity-protection", "koe-q-alive", "koe-q-safety", "koe-q-smallest-version", "koe-q-complain",
            "koe-q-embarrassing", "koe-q-tuesday", "koe-q-this-week",
        ]
        XCTAssertEqual(Set(CoachQuoteLibrary.all.map(\.id)), expected)
        XCTAssertEqual(CoachQuoteLibrary.all.filter(\.isHouseLine).count, 4)
    }

    func testHouseLinesNeverShowAnAuthorOrQuotationMarks() {
        let houses = CoachQuoteLibrary.all.filter(\.isHouseLine)
        XCTAssertEqual(houses.count, 4)
        for house in houses {
            XCTAssertTrue(house.author.isEmpty, house.id)
            XCTAssertTrue(house.source.isEmpty, house.id)
            XCTAssertNil(house.attributionNote, house.id)
            XCTAssertEqual(house.formatted, house.text, house.id)
            XCTAssertFalse(house.text.contains("“") || house.text.contains("”") || house.text.contains("\""), house.id)
            let detail = CoachMotivationItem.quote(house).detail(starterMinutes: 2)
            guard case .houseLine(let line) = detail else { return XCTFail("\(house.id) must render as a house line") }
            XCTAssertFalse(line.contains("—"), house.id)
            XCTAssertFalse(line.contains("“") || line.contains("”"), house.id)
        }
        // Attributed quotes keep their quotation marks and author.
        let quote = CoachQuoteLibrary.quote(id: "clear-systems")!
        XCTAssertEqual(CoachMotivationItem.quote(quote).detail(starterMinutes: 2), .quote(quote))
        XCTAssertTrue(quote.formatted.hasPrefix("“") && quote.formatted.hasSuffix("— James Clear"))
    }

    func testHouseLinesAppearOnlyForChallenger() {
        for situation in [CoachSituation.start, .drift, .spiral, .lateNight] {
            XCTAssertFalse(CoachQuoteLibrary.quotes(for: situation, style: .challenger).filter(\.isHouseLine).isEmpty, "\(situation) has challenger house lines")
            XCTAssertTrue(CoachQuoteLibrary.quotes(for: situation, style: .gentle).allSatisfy { !$0.isHouseLine }, "\(situation) gentle")
            XCTAssertTrue(CoachQuoteLibrary.quotes(for: situation, style: .data).allSatisfy { !$0.isHouseLine }, "\(situation) data")
        }
        // Picker: a non-Challenger style never draws a house line, however many times it picks.
        var rng = SplitMix64(seed: 7)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for style in [CoachStyle.gentle, .data] {
            for _ in 0..<200 {
                let pick = CoachQuotePicker.pick(situation: .spiral, style: style, whyLines: [], log: [], rewards: [:], now: now, using: &rng)
                if case .quote(let quote) = pick { XCTAssertFalse(quote.isHouseLine, "\(style)") }
            }
        }
        // Composer: a Gentle message never carries a house line, even when it is the only candidate.
        let house = CoachQuoteLibrary.quote(id: "house-give-it-minutes")!
        let gentle = CoachMessageComposer.compose(CoachComposerInput(
            style: .gentle, trigger: .keepGoing(step: nil), facts: CoachFacts(), target: CoachStartTarget(minutes: 20),
            quotes: [house], seed: 0, starterMinutes: 2
        ))
        XCTAssertEqual(gentle.detail, .line(CoachOnePercent.compounding))
    }

    func testHouseLineStarterLengthComesFromTheSetting() {
        let house = CoachQuoteLibrary.quote(id: "house-give-it-minutes")!
        let text = "Give it 2 minutes. If you still want to quit after that, you can."
        XCTAssertEqual(CoachMotivationItem.quote(house).detail(starterMinutes: 2), .houseLine(text))
        XCTAssertEqual(house.resolvedText(starterMinutes: 2), text)
        XCTAssertFalse(CoachMotivationItem.quote(house).detail(starterMinutes: 10).text.contains("{N}"))
        XCTAssertEqual(CoachMotivationItem.quote(house).detail(starterMinutes: 10).text, "Give it 10 minutes. If you still want to quit after that, you can.")

        // Rotation fallback path (no picker) fills {N} from the input's starter length too.
        let composed = CoachMessageComposer.compose(CoachComposerInput(
            style: .challenger, trigger: .keepGoing(step: nil), facts: CoachFacts(), target: CoachStartTarget(minutes: 20),
            quotes: [house], seed: 0, starterMinutes: 2
        ))
        XCTAssertEqual(composed.detail, .houseLine(text))

        // Pause screen: same substitution, and a plain statement with no author.
        let screen = CoachPauseScreenPresentation(style: .challenger, headline: .quote(house), fact: nil, starterMinutes: 2, attemptID: nil)
        XCTAssertEqual(screen.accessibilityText, text)
    }

    func testRotatesMyWhyAndQuotes() {
        var facts = CoachFacts()
        facts.derailer = CoachDerailerFact(name: "X", minutesThisWeek: 45) // hook is a fact, so detail rotates
        let why = ["Ship the side project by Dec"]
        let even = compose(.challenger, facts: facts, why: why, seed: 2)
        let odd = compose(.challenger, facts: facts, why: why, seed: 3)
        XCTAssertEqual(even.detail, .why("Ship the side project by Dec"))
        guard case .quote(let quote) = odd.detail else { return XCTFail("expected a quote, got \(String(describing: odd.detail))") }
        XCTAssertFalse(quote.source.isEmpty)
        XCTAssertTrue(odd.detail?.text.contains("— \(quote.author)") == true)
    }

    // MARK: Other triggers

    func testPseudoProductivityCopy() {
        let message = compose(.challenger, trigger: .pseudoProductivity(priority: "Ship v1"))
        XCTAssertEqual(message.hook, "Is this Ship v1, or does it just feel productive?")
        XCTAssertEqual(message.primaryTitle, "It's Ship v1: start a block")
        var facts = CoachFacts()
        facts.contextMinutes = 24
        facts.contextAppName = "Claude"
        XCTAssertEqual(compose(.data, trigger: .pseudoProductivity(priority: "Ship v1"), facts: facts).hook, "24m in Claude. Is this Ship v1?")
    }

    func testInSessionDriftCopy() {
        let trigger = CoachTrigger.inSessionDrift(projectName: "Side App", appName: "YouTube", minutesInApp: 7)
        XCTAssertEqual(compose(.challenger, trigger: trigger).hook, "Back to Side App.")
        XCTAssertEqual(compose(.challenger, trigger: trigger).detail, .fact("7m in YouTube this block."))
        XCTAssertEqual(compose(.data, trigger: trigger).hook, "7m in YouTube this block.")
        XCTAssertEqual(compose(.gentle, trigger: trigger).hook, "Still on Side App?")
        XCTAssertEqual(compose(.gentle, trigger: trigger).primaryTitle, "Back to it")
    }

    func testWeeklyPrioritiesInvite() {
        let message = compose(.challenger, trigger: .weeklyPriorities)
        XCTAssertEqual(message.hook, "New week. Pick 1–3 priorities.")
        XCTAssertEqual(message.primaryTitle, "Set priorities")
    }

    // MARK: Helpers

    private func richFacts() -> CoachFacts {
        var facts = CoachFacts()
        facts.streakDays = 6
        facts.hasHistory = true
        facts.sessionsToday = 2
        facts.doneMinutesToday = 101
        facts.goalMinutes = 120
        facts.pacing = CoachGoalPacing(goalMinutes: 120, doneMinutes: 101, windowMinutesLeft: 14)
        facts.minutesSinceLastSession = 75
        facts.derailer = CoachDerailerFact(name: "YouTube", minutesThisWeek: 130)
        facts.lastIntent = "Two system design mocks"
        facts.usualStartHourNow = 22
        facts.contextMinutes = 31
        facts.contextAppName = "Claude"
        return facts
    }

    private func sparseFacts() -> CoachFacts {
        var facts = CoachFacts()
        facts.goalMinutes = 150
        facts.missedYesterday = true
        facts.hasHistory = true
        facts.minutesSinceLastSession = 1500
        return facts
    }

    private func allowedNumbers(facts: CoachFacts, target: CoachStartTarget, trigger: CoachTrigger) -> Set<String> {
        var values: [Int] = [target.minutes, facts.streakDays + 1, facts.doneMinutesToday, facts.goalMinutes]
        // Constants that are not claims about the user: "1% better daily = 37×", "1–3 priorities".
        values += [1, 37, 3]
        if let pacing = facts.pacing {
            values.append(pacing.percentOfGoal)
            if let window = pacing.windowMinutesLeft { values.append(window) }
        }
        var strings = Set(values.map(String.init))
        func addDuration(_ minutes: Int) {
            numbers(in: CoachMessageComposer.duration(minutes)).forEach { strings.insert($0) }
        }
        if let since = facts.minutesSinceLastSession { addDuration(since) }
        if let derailer = facts.derailer { addDuration(derailer.minutesThisWeek) }
        if let minutes = facts.contextMinutes { strings.insert(String(minutes)) }
        if let hour = facts.usualStartHourNow { strings.insert(String(format: "%02d", hour)); strings.insert("00") }
        if case .inSessionDrift(_, _, let minutes) = trigger, let minutes { strings.insert(String(minutes)) }
        if case .weeklyPriorities = trigger { strings.insert("30") }
        return strings
    }

    private func numbers(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "\\d+")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}
