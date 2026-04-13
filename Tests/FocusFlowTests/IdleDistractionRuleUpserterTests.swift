import Foundation
import Testing
@testable import FocusFlow

@Suite("IdleDistractionRuleUpserter")
struct IdleDistractionRuleUpserterTests {
    @Test("Manual upsert reuses an existing active suggestion and dismisses duplicate siblings")
    func manualUpsertReusesActiveSuggestion() {
        let now = Date(timeIntervalSince1970: 1_713_000_000)
        let activeSuggestion = IdleDistractionItem(
            key: "youtube.com",
            displayName: "YouTube",
            targetKind: .website,
            severity: .minor,
            source: .suggested,
            status: .active,
            evidenceCount: 3,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-30)
        )
        let pendingSuggestion = IdleDistractionItem(
            key: "youtube.com",
            displayName: "YouTube",
            targetKind: .website,
            severity: .major,
            source: .suggested,
            status: .pending,
            evidenceCount: 2,
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-90)
        )
        var items = [pendingSuggestion, activeSuggestion]

        let result = IdleDistractionRuleUpserter.upsert(
            items: &items,
            preferredItem: nil,
            targetKind: .website,
            key: "youtube.com",
            displayName: "YouTube",
            severity: .allowed,
            source: .manual,
            now: now
        )

        #expect(result.inserted == false)
        #expect(result.item === activeSuggestion)
        #expect(activeSuggestion.source == .manual)
        #expect(activeSuggestion.severity == .allowed)
        #expect(activeSuggestion.status == .active)
        #expect(pendingSuggestion.status == .dismissed)
        #expect(items.filter { $0.key == "youtube.com" && $0.status == .active }.count == 1)
    }
}
