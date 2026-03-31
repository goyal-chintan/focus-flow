import XCTest
import AppKit

@MainActor
final class ScreenshotAutomationScriptTests: XCTestCase {
    private struct ShellResult {
        let exitStatus: Int32
        let stdout: String
        let stderr: String
    }

    private struct ReadmeScreenshotContractRow {
        let flowID: String
        let publishedFilename: String
        let pixelWidth: Int
        let pixelHeight: Int
    }

    func testDefaultCaptureRunnerFallsBackToSwift() throws {
        let result = try runShell(
            ". Scripts/lib/screenshot-automation.sh; unset RUNNER; focusflow_resolve_capture_runner"
        )

        XCTAssertEqual(result.exitStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "swift")
    }

    func testExplicitCaptureRunnerOverridePreservesXcodebuild() throws {
        let result = try runShell(
            ". Scripts/lib/screenshot-automation.sh; RUNNER=xcodebuild; export RUNNER; focusflow_resolve_capture_runner"
        )

        XCTAssertEqual(result.exitStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "xcodebuild")
    }

    func testReadmePublishingUsesContractAndResizesArtifacts() throws {
        let contract = try loadReadmeScreenshotContract()
        XCTAssertFalse(contract.isEmpty)

        let workspaceURL = try makeScratchDirectory(named: "readme-publish")
        let sourceDirectoryURL = workspaceURL.appendingPathComponent("source", isDirectory: true)
        let outputDirectoryURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        for (index, row) in contract.enumerated() {
            let sourceFileURL = sourceDirectoryURL.appendingPathComponent("\(row.flowID).png")
            try writePNG(
                to: sourceFileURL,
                pixelWidth: row.pixelWidth + 73,
                pixelHeight: row.pixelHeight + 91,
                color: NSColor(
                    calibratedHue: CGFloat(index) / CGFloat(max(contract.count, 1)),
                    saturation: 0.75,
                    brightness: 0.9,
                    alpha: 1
                )
            )

            let sourceSize = try pixelSize(of: sourceFileURL)
            XCTAssertNotEqual(sourceSize.width, row.pixelWidth, "Test setup should require width resizing for \(row.flowID)")
            XCTAssertNotEqual(sourceSize.height, row.pixelHeight, "Test setup should require height resizing for \(row.flowID)")
        }

        let result = try runShell(
            ". Scripts/lib/screenshot-automation.sh; focusflow_publish_readme_screenshots \(shellEscaped(sourceDirectoryURL.path)) \(shellEscaped(outputDirectoryURL.path))"
        )

        XCTAssertEqual(result.exitStatus, 0, result.stderr)

        let generatedFiles = try Set(FileManager.default.contentsOfDirectory(atPath: outputDirectoryURL.path))
        XCTAssertEqual(generatedFiles, Set(contract.map(\.publishedFilename)))

        for row in contract {
            let outputFileURL = outputDirectoryURL.appendingPathComponent(row.publishedFilename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputFileURL.path), "Missing \(row.publishedFilename)")

            let imageSize = try pixelSize(of: outputFileURL)
            XCTAssertEqual(imageSize.width, row.pixelWidth, "Unexpected width for \(row.publishedFilename)")
            XCTAssertEqual(imageSize.height, row.pixelHeight, "Unexpected height for \(row.publishedFilename)")
        }
    }

    func testReadmePublishingRejectsNonNumericContractDimensions() throws {
        let workspaceURL = try makeScratchDirectory(named: "invalid-contract")
        let contractURL = workspaceURL.appendingPathComponent("invalid-contract.tsv")
        try """
        flow_id\tpublished_filename\tpixel_width\tpixel_height
        menu_bar_focusing\tmenu-bar-focusing.png\twide\t760
        """.write(to: contractURL, atomically: true, encoding: .utf8)

        let result = try runShell(
            ". Scripts/lib/screenshot-automation.sh; focusflow_publish_readme_screenshots \(shellEscaped(workspaceURL.path)) \(shellEscaped(workspaceURL.path))",
            environment: ["FOCUSFLOW_README_SCREENSHOT_CONTRACT_PATH": contractURL.path]
        )

        XCTAssertEqual(result.exitStatus, 1)
        XCTAssertTrue(result.stderr.contains("Invalid README screenshot size for menu_bar_focusing"), result.stderr)
    }

    func testReadmePublishingRejectsZeroContractDimensions() throws {
        let workspaceURL = try makeScratchDirectory(named: "zero-contract")
        let contractURL = workspaceURL.appendingPathComponent("zero-contract.tsv")
        try """
        flow_id\tpublished_filename\tpixel_width\tpixel_height
        menu_bar_focusing\tmenu-bar-focusing.png\t0\t760
        """.write(to: contractURL, atomically: true, encoding: .utf8)

        let result = try runShell(
            ". Scripts/lib/screenshot-automation.sh; focusflow_publish_readme_screenshots \(shellEscaped(workspaceURL.path)) \(shellEscaped(workspaceURL.path))",
            environment: ["FOCUSFLOW_README_SCREENSHOT_CONTRACT_PATH": contractURL.path]
        )

        XCTAssertEqual(result.exitStatus, 1)
        XCTAssertTrue(result.stderr.contains("Invalid README screenshot size for menu_bar_focusing"), result.stderr)
    }

    func testReadmePublishingReportsFlowWhenResizeFails() throws {
        let workspaceURL = try makeScratchDirectory(named: "resize-failure")
        let sourceDirectoryURL = workspaceURL.appendingPathComponent("source", isDirectory: true)
        let outputDirectoryURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let contractURL = workspaceURL.appendingPathComponent("resize-contract.tsv")

        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try "not a png".write(
            to: sourceDirectoryURL.appendingPathComponent("menu_bar_focusing.png"),
            atomically: true,
            encoding: .utf8
        )
        try """
        flow_id\tpublished_filename\tpixel_width\tpixel_height
        menu_bar_focusing\tmenu-bar-focusing.png\t342\t760
        """.write(to: contractURL, atomically: true, encoding: .utf8)

        let result = try runShell(
            ". Scripts/lib/screenshot-automation.sh; focusflow_publish_readme_screenshots \(shellEscaped(sourceDirectoryURL.path)) \(shellEscaped(outputDirectoryURL.path))",
            environment: ["FOCUSFLOW_README_SCREENSHOT_CONTRACT_PATH": contractURL.path]
        )

        XCTAssertEqual(result.exitStatus, 1)
        XCTAssertTrue(result.stderr.contains("Failed to publish screenshot for menu_bar_focusing"), result.stderr)
        XCTAssertTrue(
            (try? FileManager.default.contentsOfDirectory(atPath: outputDirectoryURL.path).isEmpty) ?? true,
            "Failed publish should not leave partial output artifacts behind."
        )
    }

    private func loadReadmeScreenshotContract() throws -> [ReadmeScreenshotContractRow] {
        let contractURL = repoRootURL
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent("readme-screenshot-contract.tsv")
        let contents = try String(contentsOf: contractURL, encoding: .utf8)

        return try contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { return nil }

                let columns = trimmedLine
                    .split(separator: "\t", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

                guard columns.first != "flow_id" else { return nil }
                guard columns.count == 4 else {
                    throw NSError(
                        domain: "ScreenshotAutomationScriptTests",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid contract row: \(trimmedLine)"]
                    )
                }

                guard let pixelWidth = Int(columns[2]), let pixelHeight = Int(columns[3]) else {
                    throw NSError(
                        domain: "ScreenshotAutomationScriptTests",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid screenshot size in row: \(trimmedLine)"]
                    )
                }

                return ReadmeScreenshotContractRow(
                    flowID: columns[0],
                    publishedFilename: columns[1],
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight
                )
            }
    }

    private func runShell(
        _ command: String,
        environment: [String: String] = [:]
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = repoRootURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ShellResult(exitStatus: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func makeScratchDirectory(named name: String) throws -> URL {
        let directoryURL = repoRootURL
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("screenshot-automation-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL
    }

    private func writePNG(
        to url: URL,
        pixelWidth: Int,
        pixelHeight: Int,
        color: NSColor
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw NSError(
                domain: "ScreenshotAutomationScriptTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap context"]
            )
        }

        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        guard let image = context.makeImage() else {
            throw NSError(
                domain: "ScreenshotAutomationScriptTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create image"]
            )
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "ScreenshotAutomationScriptTests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"]
            )
        }

        try data.write(to: url)
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let data = try Data(contentsOf: url)
        guard let bitmap = NSBitmapImageRep(data: data) else {
            throw NSError(
                domain: "ScreenshotAutomationScriptTests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Unable to decode image at \(url.path)"]
            )
        }
        return (bitmap.pixelsWide, bitmap.pixelsHigh)
    }

    private func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
