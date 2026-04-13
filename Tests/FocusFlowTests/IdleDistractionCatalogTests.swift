import Testing
@testable import FocusFlow

@Suite("IdleDistractionCatalog")
struct IdleDistractionCatalogTests {
    @Test("Accepted manual rule overrides pending suggestion")
    func manualRuleWins() {
        let catalog = IdleDistractionCatalog(items: [
            .suggestedWebsite("youtube.com", severity: .major),
            .manualWebsite("youtube.com", severity: .allowed)
        ])

        let resolution = catalog.resolution(for: .website("youtube.com"))
        #expect(resolution.severity == .some(.allowed))
    }

    @Test("Pending suggestions do not enforce idle severity")
    func pendingSuggestionDoesNotEnforce() {
        let catalog = IdleDistractionCatalog(items: [
            .suggestedApp("com.mitchellh.ghostty", severity: .major)
        ])

        let resolution = catalog.resolution(for: .app("com.mitchellh.ghostty"))
        #expect(resolution.severity == nil)
    }

    @Test("Repeated idle evidence creates a suggestion but not an active rule")
    func repeatedEvidenceCreatesSuggestion() {
        var catalog = IdleDistractionCatalog(items: [])

        catalog.recordIdleEvidence(
            target: .website("youtube.com"),
            displayName: "YouTube",
            outcome: .ignoredNudge
        )
        catalog.recordIdleEvidence(
            target: .website("youtube.com"),
            displayName: "YouTube",
            outcome: .ignoredNudge
        )

        let resolution = catalog.resolution(for: .website("youtube.com"))
        #expect(resolution.hasSuggestion == true)
        #expect(resolution.severity == nil)
    }
}
