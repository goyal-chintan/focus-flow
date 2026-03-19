import XCTest
@testable import FocusFlow2

@MainActor
final class DesignLabIntegrationTests: XCTestCase {
    func testEndToEndDecisionFlowRoundTripsStoreSerializationAndLogs() throws {
        try DesignLabTestSupport.withTemporaryHome {
            let store = FFDesignLabStore()
            let logStore = VariantLabLogStore.shared

            let baseTokens = FFDesignTokens()
            let tunedTokens = makeTunedTokens()
            let variant = FFDesignVariant(name: "Timer Ring A", description: "Integration test", tokens: tunedTokens)

            store.pushUndo(baseTokens)
            store.save(variant)
            XCTAssertEqual(store.variants.count, 1)

            store.setActive(variant, applying: baseTokens)
            XCTAssertEqual(baseTokens, tunedTokens)

            let exportedJSON = try XCTUnwrap(store.exportJSON(baseTokens))
            let importedTokens = try XCTUnwrap(store.importJSON(exportedJSON))
            XCTAssertEqual(importedTokens, tunedTokens)

            let activeIDPath = DesignLabTestSupport.designLabRoot()
                .appendingPathComponent("active-variant-id.txt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: activeIDPath.path))
            XCTAssertEqual(DesignLabTestSupport.readString(activeIDPath)?.trimmingCharacters(in: .whitespacesAndNewlines), variant.id.uuidString)

            let record = VariantLabDecisionRecord(
                timestamp: Date(timeIntervalSince1970: 1_700_000_321),
                roundName: "Integration",
                scenario: .running,
                component: .timerRing,
                variant: VariantLabMenuVariant.variantA.rawValue,
                motionSpeed: .x1,
                action: .keep,
                notes: "Use the tuned winner.",
                interaction: VariantLabInteractionSnapshot(
                    isExpanded: true,
                    hoverPreview: true,
                    pressPreview: false,
                    transitionStep: 2
                )
            )

            let logURL = try logStore.appendDecision(record)
            XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
            XCTAssertTrue(DesignLabTestSupport.readString(logURL)?.contains("Use the tuned winner.") ?? false)

            store.delete(variant)
            XCTAssertEqual(store.variants.count, 0)
            XCTAssertNil(store.activeVariantId)
        }
    }

    func testLockedVariantSurvivesSaveLoadAndNoOpDeleteOfMissingVariant() throws {
        try DesignLabTestSupport.withTemporaryHome {
            let store = FFDesignLabStore()
            var variant = FFDesignVariant(name: "Locked", tokens: makeTunedTokens())
            variant.isLocked = true

            store.save(variant)
            store.loadAll()
            XCTAssertEqual(store.variants.first?.isLocked, true)

            let missing = FFDesignVariant(name: "Missing", tokens: FFDesignTokens())
            store.delete(missing)
            XCTAssertEqual(store.variants.count, 1)
        }
    }

    private func makeTunedTokens() -> FFDesignTokens {
        let tokens = FFDesignTokens()
        tokens.spacing.md = 18
        tokens.radius.card = 20
        tokens.sizing.controlMin = 46
        tokens.ring.size = 218
        tokens.ring.strokeWidth = 5.3
        tokens.ring.timerFontSize = 64
        tokens.typography.metaSize = 14
        tokens.color.panelFillOpacity = 0.06
        tokens.color.panelBorderOpacity = 0.11
        tokens.motion.popoverResponse = 0.38
        tokens.motion.breathingDuration = 1.9
        tokens.layout.popoverWidth = 352
        return tokens
    }
}
