import XCTest
@testable import FocusFlow2

@MainActor
final class VariantLabLogStoreTests: XCTestCase {
    func testAppendDecisionWritesJsonlAndMarkdownUnderVariantLabRoot() throws {
        try DesignLabTestSupport.withTemporaryHome {
            let store = VariantLabLogStore(rootDirectory: DesignLabTestSupport.variantLabRoot())
            let record = makeRecord(component: .timerRing, variant: VariantLabMenuVariant.variantA.rawValue, action: .keep, round: "1")
            let markdownURL = try store.appendDecision(record)
            let jsonlURL = DesignLabTestSupport.variantLabRoot().appendingPathComponent("decision-log.jsonl")

            XCTAssertTrue(markdownURL.path.hasSuffix("FocusFlow2/VariantLab/decision-log.md"))
            XCTAssertTrue(jsonlURL.path.hasSuffix("FocusFlow2/VariantLab/decision-log.jsonl"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: markdownURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: jsonlURL.path))

            let markdown = try XCTUnwrap(DesignLabTestSupport.readString(markdownURL))
            let jsonl = try XCTUnwrap(DesignLabTestSupport.readString(jsonlURL))

            XCTAssertTrue(markdown.contains("Scenario: Idle"))
            XCTAssertTrue(markdown.contains("Component: Timer Ring"))
            XCTAssertTrue(markdown.contains("Variant: A"))
            XCTAssertTrue(markdown.contains("Action: Keep"))
            XCTAssertTrue(jsonl.contains("\"component\":\"timerRing\"") || jsonl.contains("\"component\":\"Timer Ring\""))
            XCTAssertEqual(store.latestLogPath()?.path, markdownURL.path)
        }
    }

    func testAppendDecisionAppendsMultipleRecords() throws {
        try DesignLabTestSupport.withTemporaryHome {
            let store = VariantLabLogStore(rootDirectory: DesignLabTestSupport.variantLabRoot())
            let first = makeRecord(component: .motion, variant: VariantLabMenuVariant.variantB.rawValue, action: .reject, round: "1")
            let second = makeRecord(component: .motion, variant: VariantLabMenuVariant.variantC.rawValue, action: .needsTweak, round: "2")

            let markdownURL = try store.appendDecision(first)
            _ = try store.appendDecision(second)

            let markdown = try XCTUnwrap(DesignLabTestSupport.readString(markdownURL))
            let entryCount = markdown.components(separatedBy: "## ").count - 1

            XCTAssertEqual(entryCount, 2)
            XCTAssertTrue(markdown.contains("Round 1"))
            XCTAssertTrue(markdown.contains("Round 2"))
        }
    }

    private func makeRecord(
        component: VariantLabComponent,
        variant: String,
        action: VariantLabDecisionAction,
        round: String
    ) -> VariantLabDecisionRecord {
        VariantLabDecisionRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_123),
            roundName: round,
            scenario: .idle,
            component: component,
            variant: variant,
            motionSpeed: .x1,
            action: action,
            notes: "Decision note",
            interaction: VariantLabInteractionSnapshot(
                isExpanded: true,
                hoverPreview: false,
                pressPreview: false,
                transitionStep: 1
            )
        )
    }
}
