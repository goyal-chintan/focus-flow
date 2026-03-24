import Testing
import Foundation
@testable import FocusFlow

@Suite("ProjectContextRisk Block Recommendations")
struct ProjectContextRiskTests {

    @Test("shouldRecommendBlock fires after 2 avoidant events in 7 days")
    func blockRecommendationAfterTwoAvoidantEvents() {
        var risk = ProjectContextRisk(
            projectId: UUID(),
            workMode: .deepWork,
            contextKey: "youtube.com",
            contextDisplayName: "YouTube"
        )

        risk.avoidantDates = [Date(), Date()]

        #expect(risk.shouldRecommendBlock == true)
    }

    @Test("shouldRecommendBlock does not fire after only 1 avoidant event")
    func noBlockRecommendationAfterOneEvent() {
        var risk = ProjectContextRisk(
            projectId: UUID(),
            workMode: .deepWork,
            contextKey: "youtube.com",
            contextDisplayName: "YouTube"
        )

        risk.avoidantDates = [Date()]

        #expect(risk.shouldRecommendBlock == false)
    }

    @Test("shouldRecommendBlock fires when missedStartCorrelation >= 1")
    func blockRecommendationAfterMissedStart() {
        var risk = ProjectContextRisk(
            projectId: UUID(),
            workMode: .learning,
            contextKey: "twitter.com",
            contextDisplayName: "Twitter"
        )

        risk.missedStartCorrelationCount = 1

        #expect(risk.shouldRecommendBlock == true)
    }

    @Test("shouldRecommendAllow fires after 2 planned confirmations in 14 days")
    func allowRecommendationAfterTwoPlanned() {
        var risk = ProjectContextRisk(
            projectId: UUID(),
            workMode: .deepWork,
            contextKey: "docs.google.com",
            contextDisplayName: "Google Docs"
        )

        risk.plannedDates = [Date(), Date()]

        #expect(risk.shouldRecommendAllow == true)
    }

    @Test("shouldRecommendAllow does not fire after only 1 planned")
    func noAllowRecommendationAfterOnePlanned() {
        var risk = ProjectContextRisk(
            projectId: UUID(),
            workMode: .deepWork,
            contextKey: "docs.google.com",
            contextDisplayName: "Google Docs"
        )

        risk.plannedDates = [Date()]

        #expect(risk.shouldRecommendAllow == false)
    }
}
