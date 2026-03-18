import XCTest
@testable import FocusFlow2

final class VariantLabLayoutBenchTests: XCTestCase {
    func testLayoutComponentMetadataDescribesMenuSliderBench() throws {
        let layout = try XCTUnwrap(VariantLabComponent(rawValue: "Layout"))

        XCTAssertEqual(layout.rawValue, "Layout")
        XCTAssertEqual(layout.subtitle, "Menu slider placement, spacing, and control shapes")
        XCTAssertEqual(layout.reviewPrompt, "Compare the same menu slider in different shapes before you freeze the layout.")
        XCTAssertEqual(layout.checklistItems.count, 4)
        XCTAssertTrue(layout.variantTitle(for: .variantA).contains("Floating"))
        XCTAssertTrue(layout.variantTitle(for: .variantB).contains("Balanced"))
        XCTAssertTrue(layout.variantTitle(for: .variantC).contains("Compact"))
    }

    func testLayoutDecisionRecordCanLogLayoutComponent() throws {
        let layout = try XCTUnwrap(VariantLabComponent(rawValue: "Layout"))
        let record = VariantLabDecisionRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_222),
            roundName: "Layout",
            scenario: .idle,
            component: layout,
            variant: .variantB,
            motionSpeed: .x1,
            action: .keep,
            ratings: Dictionary(uniqueKeysWithValues: VariantLabCriterion.allCases.map { ($0.rawValue, 4) }),
            notes: "Balanced rail reads best for the popover.",
            interaction: VariantLabInteractionSnapshot(
                isExpanded: true,
                hoverPreview: false,
                pressPreview: false,
                transitionStep: 0
            )
        )

        XCTAssertTrue(record.markdownEntry.contains("Component: Layout"))
        XCTAssertTrue(record.markdownEntry.contains("Variant: B"))
        XCTAssertTrue(record.markdownEntry.contains("Balanced rail"))
    }
}
