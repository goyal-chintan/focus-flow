import XCTest
@testable import FocusFlow2

final class FFBuildInfoTests: XCTestCase {
    func testBuildInfoReadsBundleKeysAndFallsBackToBundleVersion() {
        let keyed = FFBuildInfo(bundleInfo: [
            "FFBuildSHA": "6b4c7d9",
            "FFBuildTimestampUTC": "20260319T121500Z"
        ])

        XCTAssertEqual(keyed.shortGitSHA, "6b4c7d9")
        XCTAssertEqual(keyed.timestampUTC, "20260319T121500Z")
        XCTAssertEqual(keyed.displayString, "6b4c7d9 · 20260319T121500Z")

        let fallback = FFBuildInfo(bundleInfo: [
            "CFBundleVersion": "86d678a"
        ])

        XCTAssertEqual(fallback.shortGitSHA, "86d678a")
        XCTAssertEqual(fallback.timestampUTC, "unknown")
        XCTAssertEqual(fallback.displayString, "86d678a · unknown")
    }

    func testBundleScriptsWriteDeterministicBuildMetadataKeys() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for scriptName in ["run.sh", "run_focusflow2.sh"] {
            let scriptURL = repoRoot.appendingPathComponent("Scripts").appendingPathComponent(scriptName)
            let script = try String(contentsOf: scriptURL, encoding: .utf8)

            XCTAssertTrue(script.contains("FFBuildSHA"), scriptName)
            XCTAssertTrue(script.contains("FFBuildTimestampUTC"), scriptName)
            XCTAssertTrue(script.contains("git rev-parse --short HEAD"), scriptName)
            XCTAssertTrue(script.contains("date -u"), scriptName)
        }
    }
}
