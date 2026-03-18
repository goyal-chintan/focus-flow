import XCTest
@testable import FocusFlow2

@MainActor
final class DesignLabStorageGuardrailTests: XCTestCase {
    func testDesignLabStoreUsesFocusFlow2DesignLabDirectoryOnly() throws {
        try DesignLabTestSupport.withTemporaryHome {
            let store = FFDesignLabStore()
            var variant = FFDesignVariant(name: "Guardrail", tokens: FFDesignTokens())
            variant.isLocked = true
            store.save(variant)

            let root = DesignLabTestSupport.designLabRoot()
            let variantFile = root
                .appendingPathComponent("variants", isDirectory: true)
                .appendingPathComponent("\(variant.id.uuidString).json")

            XCTAssertTrue(root.path.contains("FocusFlow2/DesignLab"))
            XCTAssertFalse(root.path.contains("FocusFlow/DesignLab"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: variantFile.path))
            XCTAssertTrue(variantFile.path.contains("FocusFlow2/DesignLab/variants"))
        }
    }

    func testVariantLabLogStoreUsesFocusFlow2VariantLabDirectoryOnly() throws {
        try DesignLabTestSupport.withTemporaryHome {
            let store = VariantLabLogStore.shared
            let record = VariantLabDecisionRecord(
                timestamp: Date(timeIntervalSince1970: 1_700_000_555),
                roundName: "Guardrail",
                scenario: .paused,
                component: .motion,
                variant: .variantC,
                motionSpeed: .x05,
                action: .reject,
                ratings: Dictionary(uniqueKeysWithValues: VariantLabCriterion.allCases.map { ($0.rawValue, 2) }),
                notes: "",
                interaction: VariantLabInteractionSnapshot(
                    isExpanded: false,
                    hoverPreview: false,
                    pressPreview: false,
                    transitionStep: 0
                )
            )

            let markdownURL = try store.appendDecision(record)
            let root = DesignLabTestSupport.variantLabRoot()

            XCTAssertTrue(root.path.contains("FocusFlow2/VariantLab"))
            XCTAssertFalse(root.path.contains("FocusFlow/VariantLab"))
            XCTAssertTrue(markdownURL.path.contains("FocusFlow2/VariantLab"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("decision-log.jsonl").path))
        }
    }
}
