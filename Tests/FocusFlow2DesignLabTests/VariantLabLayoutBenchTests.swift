import XCTest
@testable import FocusFlow2

final class VariantLabLayoutBenchTests: XCTestCase {
    func testLayoutVariantMetadataDescribesFiveDistinctLayouts() throws {
        XCTAssertEqual(VariantLabLayoutVariant.allCases.count, 5)

        let titles = VariantLabLayoutVariant.allCases.map(\.layoutTitle)
        XCTAssertEqual(titles.count, 5)
        XCTAssertTrue(titles[0].contains("A"))
        XCTAssertTrue(titles[4].contains("E"))

        let subtitles = VariantLabLayoutVariant.allCases.map(\.layoutSubtitle)
        XCTAssertEqual(subtitles.count, 5)
        XCTAssertTrue(subtitles.allSatisfy { !$0.isEmpty })
    }

    func testLayoutComponentMetadataDescribesMenuSliderFlow() throws {
        let layout = try XCTUnwrap(VariantLabComponent(rawValue: "Layout"))

        XCTAssertEqual(layout.rawValue, "Layout")
        XCTAssertEqual(layout.subtitle, "Menu slider placement, spacing, and control shapes")
        XCTAssertEqual(layout.reviewPrompt, "Compare the same menu slider in different shapes before you freeze the layout.")
        XCTAssertEqual(layout.checklistItems.count, 4)
        XCTAssertTrue(layout.layoutPreviewTitle(for: .variantA).contains("Floating"))
        XCTAssertTrue(layout.layoutPreviewTitle(for: .variantB).contains("Balanced"))
        XCTAssertTrue(layout.layoutPreviewTitle(for: .variantC).contains("Compact"))
    }

    func testLayoutDecisionRecordCanLogLayoutComponent() throws {
        let layout = try XCTUnwrap(VariantLabComponent(rawValue: "Layout"))
        let record = VariantLabDecisionRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_222),
            roundName: "Layout",
            scenario: .idle,
            component: layout,
            variant: VariantLabLayoutVariant.variantB.rawValue,
            motionSpeed: .x1,
            action: .keep,
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
