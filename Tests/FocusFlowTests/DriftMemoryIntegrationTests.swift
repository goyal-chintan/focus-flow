import Testing
import Foundation
@testable import FocusFlow

@Suite("DriftMemory Integration — Spec Learning Rules")
struct DriftMemoryIntegrationTests {

    // MARK: - Helpers

    /// Returns a fresh DriftMemoryStore with an isolated UserDefaults suite so tests don't
    /// pollute each other or the real app storage.
    private func makeStore() -> DriftMemoryStore {
        let suiteName = "test.driftmemory.\(UUID().uuidString)"
        return DriftMemoryStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    // MARK: - No global allowlist rule

    @Test("Suspicious context is not globally whitelisted after single session confirmation")
    func noGlobalAllowlistFromOneConfirmation() {
        let store = makeStore()
        let project1 = UUID()
        let project2 = UUID()

        // User confirms YouTube is planned on project1
        store.recordPlanned(projectId: project1, workMode: .deepWork, appOrDomain: "youtube.com")

        // project1 session-scoped — should be allowed in same session
        #expect(store.sessionScopedAllowance(projectId: project1, workMode: .deepWork, appOrDomain: "youtube.com") == true)

        // project2 — must NOT be allowed (no global allowlist)
        #expect(store.sessionScopedAllowance(projectId: project2, workMode: .deepWork, appOrDomain: "youtube.com") == false)
        #expect(store.projectScopedAllowance(projectId: project2, workMode: .deepWork, appOrDomain: "youtube.com") == false)
    }

    @Test("Two planned confirmations in 14 days grant project-scoped allowance only for that project")
    func twoPlannedGrantsProjectScopedOnly() {
        let store = makeStore()
        let project1 = UUID()
        let project2 = UUID()

        store.recordPlanned(projectId: project1, workMode: .learning, appOrDomain: "docs.google.com")
        store.recordPlanned(projectId: project1, workMode: .learning, appOrDomain: "docs.google.com")

        #expect(store.projectScopedAllowance(projectId: project1, workMode: .learning, appOrDomain: "docs.google.com") == true)
        // Different project must not be affected
        #expect(store.projectScopedAllowance(projectId: project2, workMode: .learning, appOrDomain: "docs.google.com") == false)
    }

    @Test("Two avoidant confirmations in 7 days produce project-scoped risk memory")
    func twoAvoidantProducesProjectRisk() {
        let store = makeStore()
        let projectId = UUID()

        store.recordAvoidant(projectId: projectId, workMode: .deepWork, appOrDomain: "twitter.com")
        store.recordAvoidant(projectId: projectId, workMode: .deepWork, appOrDomain: "twitter.com")

        #expect(store.projectScopedRisk(projectId: projectId, workMode: .deepWork, appOrDomain: "twitter.com") == true)
    }

    @Test("beginSession resets session-scoped allowances")
    func beginSessionResetsSessionAllowances() {
        let store = makeStore()
        let projectId = UUID()

        store.recordPlanned(projectId: projectId, workMode: .deepWork, appOrDomain: "youtube.com")
        #expect(store.sessionScopedAllowance(projectId: projectId, workMode: .deepWork, appOrDomain: "youtube.com") == true)

        // New session starts
        store.beginSession()

        // Session-scoped allowance no longer valid (new sessionStart is now)
        // Since recordPlanned happened before beginSession(), it's outside new session window
        #expect(store.sessionScopedAllowance(projectId: projectId, workMode: .deepWork, appOrDomain: "youtube.com") == false)
    }

    @Test("Repeated pattern stays project-scoped and does not leak globally")
    func repeatedPatternIsProjectScopedOnly() {
        let store = makeStore()
        let project1 = UUID()
        let project2 = UUID()
        let context = "youtube.com"

        store.recordAvoidant(projectId: project1, workMode: .deepWork, appOrDomain: context)
        store.recordAvoidant(projectId: project1, workMode: .deepWork, appOrDomain: context)

        #expect(store.projectScopedRisk(projectId: project1, workMode: .deepWork, appOrDomain: context) == true)
        #expect(store.projectScopedRisk(projectId: project2, workMode: .deepWork, appOrDomain: context) == false)
        #expect(store.projectScopedRisk(projectId: nil, workMode: nil, appOrDomain: context) == false)
    }
}
