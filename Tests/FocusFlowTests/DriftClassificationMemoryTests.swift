import Testing
import Foundation
@testable import FocusFlow

@Suite("DriftClassificationMemory Learning Rules")
struct DriftClassificationMemoryTests {

    // MARK: - Session-scoped allowance

    @Test("1 planned confirmation grants session-scoped allowance only")
    func onePlannedGrantsSessionAllowance() {
        var memory = DriftClassificationMemory()
        let sessionStart = Date()
        let key = DriftClassificationMemory.key(projectId: nil, workMode: .deepWork, appOrDomain: "youtube.com")

        memory.recordPlanned(key: key)

        #expect(memory.sessionScopedAllowance(key: key, sessionStart: sessionStart) == true)
        // Must NOT yet grant project-scoped allowance
        #expect(memory.projectScopedAllowance(key: key) == false)
    }

    @Test("Session-scoped allowance does not apply to previous session")
    func sessionAllowanceDoesNotCarryOver() {
        var memory = DriftClassificationMemory()
        let key = DriftClassificationMemory.key(projectId: nil, workMode: .learning, appOrDomain: "reddit.com")

        // Record planned 30 minutes ago (within old session, before current session)
        // Simulate by recording then checking with a future session start
        memory.recordPlanned(key: key)
        let newSessionStart = Date()  // new session started NOW, after recording

        // The planned event was before newSessionStart — not in current session
        // Wait: recordPlanned uses Date() internally. To test this properly we verify
        // that sessionStart AFTER the record means no session-scoped allowance.
        // Since recordPlanned stamps Date() at call time, and newSessionStart is after,
        // session-scoped allowance should be false.
        #expect(memory.sessionScopedAllowance(key: key, sessionStart: newSessionStart) == false)
    }

    // MARK: - Project-scoped allowance

    @Test("2 planned confirmations in 14 days grants project-scoped allowance")
    func twoPlannedGrantsProjectAllowance() {
        var memory = DriftClassificationMemory()
        let key = DriftClassificationMemory.key(projectId: UUID(), workMode: .deepWork, appOrDomain: "docs.google.com")

        memory.recordPlanned(key: key)
        memory.recordPlanned(key: key)

        #expect(memory.projectScopedAllowance(key: key) == true)
    }

    @Test("1 planned confirmation does not grant project-scoped allowance")
    func onePlannedDoesNotGrantProjectAllowance() {
        var memory = DriftClassificationMemory()
        let key = DriftClassificationMemory.key(projectId: UUID(), workMode: .admin, appOrDomain: "notion.so")

        memory.recordPlanned(key: key)

        #expect(memory.projectScopedAllowance(key: key) == false)
    }

    @Test("Project-scoped allowance expires after 14 days")
    func projectAllowanceExpiresAfter14Days() throws {
        // This test validates the window constant — we can't inject time so we verify
        // the constant is correct
        #expect(DriftClassificationMemory.projectScopedAllowanceWindow == 14 * 24 * 3600)
        #expect(DriftClassificationMemory.projectScopedAllowanceCount == 2)
    }

    // MARK: - Project-scoped risk

    @Test("2 avoidant confirmations in 7 days triggers project-scoped risk")
    func twoAvoidantTriggersProjectRisk() {
        var memory = DriftClassificationMemory()
        let key = DriftClassificationMemory.key(projectId: UUID(), workMode: .deepWork, appOrDomain: "youtube.com")

        memory.recordAvoidant(key: key)
        memory.recordAvoidant(key: key)

        #expect(memory.projectScopedRisk(key: key) == true)
    }

    @Test("1 avoidant confirmation does not trigger project-scoped risk")
    func oneAvoidantDoesNotTriggerRisk() {
        var memory = DriftClassificationMemory()
        let key = DriftClassificationMemory.key(projectId: UUID(), workMode: .creative, appOrDomain: "twitter.com")

        memory.recordAvoidant(key: key)

        #expect(memory.projectScopedRisk(key: key) == false)
    }

    @Test("Avoidant risk window is 7 days")
    func avoidantRiskWindowIs7Days() {
        #expect(DriftClassificationMemory.projectScopedRiskWindow == 7 * 24 * 3600)
        #expect(DriftClassificationMemory.projectScopedRiskCount == 2)
    }

    // MARK: - Key isolation

    @Test("Different projects have isolated memories")
    func projectMemoriesAreIsolated() {
        var memory = DriftClassificationMemory()
        let project1 = UUID()
        let project2 = UUID()
        let key1 = DriftClassificationMemory.key(projectId: project1, workMode: .deepWork, appOrDomain: "youtube.com")
        let key2 = DriftClassificationMemory.key(projectId: project2, workMode: .deepWork, appOrDomain: "youtube.com")

        memory.recordAvoidant(key: key1)
        memory.recordAvoidant(key: key1)

        #expect(memory.projectScopedRisk(key: key1) == true)
        #expect(memory.projectScopedRisk(key: key2) == false, "Different project must have separate memory")
    }

    @Test("No global allowlist from single confirmation")
    func noGlobalAllowlist() {
        var memory = DriftClassificationMemory()
        let projectId = UUID()
        let key = DriftClassificationMemory.key(projectId: projectId, workMode: .deepWork, appOrDomain: "youtube.com")
        let globalKey = DriftClassificationMemory.key(projectId: nil, workMode: nil, appOrDomain: "youtube.com")

        memory.recordPlanned(key: key)
        memory.recordPlanned(key: key)

        // Project-scoped allowance is granted for this project
        #expect(memory.projectScopedAllowance(key: key) == true)
        // But NOT for nil/global key — no global allowlist
        #expect(memory.projectScopedAllowance(key: globalKey) == false)
    }
}
