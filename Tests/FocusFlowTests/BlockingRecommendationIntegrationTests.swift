import Testing
import Foundation
@testable import FocusFlow

@Suite("Blocking Recommendation — Evidence Thresholds")
struct BlockingRecommendationIntegrationTests {

    private func makeEngine() -> FocusCoachBlockingRecommendationEngine {
        let suiteName = "test.blockingrec.\(UUID().uuidString)"
        return FocusCoachBlockingRecommendationEngine(defaults: UserDefaults(suiteName: suiteName)!)
    }

    @Test("Block recommendation fires after 2 avoidant events in 7 days")
    func blockRecAfterTwoAvoidant() {
        let engine = makeEngine()
        let projectId = UUID()
        let contextKey = "youtube.com"

        engine.recordAvoidant(projectId: projectId, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: projectId, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")

        let rec = engine.blockRecommendation(for: contextKey)
        #expect(rec != nil)
        #expect(rec?.kind == .block)
        #expect(rec?.copyText.contains("YouTube") == true)
    }

    @Test("Block recommendation does not fire after only 1 avoidant event")
    func noBlockRecAfterOneAvoidant() {
        let engine = makeEngine()
        let projectId = UUID()
        let contextKey = "youtube.com"

        engine.recordAvoidant(projectId: projectId, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")

        #expect(engine.blockRecommendation(for: contextKey) == nil)
    }

    @Test("Block recommendation fires immediately after missed start")
    func blockRecAfterMissedStart() {
        let engine = makeEngine()
        let projectId = UUID()
        let contextKey = "twitter.com"

        engine.recordMissedStart(projectId: projectId, workMode: .deepWork, contextKey: contextKey, displayName: "Twitter")

        let rec = engine.blockRecommendation(for: contextKey)
        #expect(rec != nil)
        #expect(rec?.copyText.contains("missed start") == true || rec?.copyText.contains("Twitter") == true)
    }

    @Test("Allow recommendation fires after 2 planned confirmations in 14 days")
    func allowRecAfterTwoPlanned() {
        let engine = makeEngine()
        let projectId = UUID()
        let contextKey = "github.com"

        engine.recordPlanned(projectId: projectId, workMode: .deepWork, contextKey: contextKey, displayName: "GitHub")
        engine.recordPlanned(projectId: projectId, workMode: .deepWork, contextKey: contextKey, displayName: "GitHub")

        let rec = engine.allowRecommendation(for: contextKey)
        #expect(rec != nil)
        #expect(rec?.kind == .allow)
    }

    @Test("Block recommendation is never global — keyed by context only")
    func blockRecIsProjectScoped() {
        let engine = makeEngine()
        let project1 = UUID()
        let project2 = UUID()
        let contextKey = "youtube.com"

        // Avoidant events on project1
        engine.recordAvoidant(projectId: project1, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: project1, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")

        // Recommendation fires for the context key (associated with project1)
        let rec = engine.blockRecommendation(for: contextKey)
        #expect(rec != nil)
        #expect(rec?.projectId == project1)

        // project2 has its own distinct context key — no events recorded, so no recommendation
        let contextKey2 = "\(project2.uuidString)|deep_work|youtube.com"
        #expect(engine.blockRecommendation(for: contextKey2) == nil)
    }

    @Test("markRecommendationSurfaced uses exact project/workMode tuple when context overlaps")
    func markRecommendationSurfacedIsDeterministicForSharedContext() {
        let engine = makeEngine()
        let project1 = UUID()
        let project2 = UUID()
        let contextKey = "youtube.com"

        engine.recordAvoidant(projectId: project1, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: project1, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: project2, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: project2, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")

        #expect(engine.blockRecommendation(for: contextKey, projectId: project1, workMode: .deepWork) != nil)
        #expect(engine.blockRecommendation(for: contextKey, projectId: project2, workMode: .deepWork) != nil)

        engine.markRecommendationSurfaced(projectId: project1, workMode: .deepWork, contextKey: contextKey)

        #expect(engine.blockRecommendation(for: contextKey, projectId: project1, workMode: .deepWork) == nil)
        #expect(engine.blockRecommendation(for: contextKey, projectId: project2, workMode: .deepWork) != nil)
    }

    @Test("fallback surfacing is safe no-op when context is ambiguous across projects")
    func fallbackSurfacingNoOpsForAmbiguousContext() {
        let engine = makeEngine()
        let project1 = UUID()
        let project2 = UUID()
        let contextKey = "youtube.com"

        engine.recordAvoidant(projectId: project1, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: project1, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: project2, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")
        engine.recordAvoidant(projectId: project2, workMode: .deepWork, contextKey: contextKey, displayName: "YouTube")

        #expect(engine.blockRecommendation(for: contextKey) == nil)

        engine.markRecommendationSurfaced(contextKey: contextKey)

        #expect(engine.blockRecommendation(for: contextKey, projectId: project1, workMode: .deepWork) != nil)
        #expect(engine.blockRecommendation(for: contextKey, projectId: project2, workMode: .deepWork) != nil)
    }
}
