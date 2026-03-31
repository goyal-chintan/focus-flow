import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class ScreenshotAutomationScriptTests: XCTestCase {
    private struct ContractRow {
        let flowID: String
        let appearance: String
        let sourceWidth: Int
        let sourceHeight: Int
        let outputPath: String
        let outputWidth: Int
        let outputHeight: Int
    }

    private struct ImageDimensions: Equatable {
        let width: Int
        let height: Int
    }

    private struct ShellResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private enum TestError: Error {
        case invalidContractRow(String)
        case imageWriteFailed(String)
        case imageReadFailed(String)
    }

    func testDefaultRunnerResolutionReturnsSwiftWhenRUNNERIsUnset() throws {
        let result = try runHelperCommand("unset RUNNER\nfocusflow_screenshot_resolve_runner")
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "swift")
    }

    func testExplicitRunnerOverridePreservesXcodebuild() throws {
        let result = try runHelperCommand("RUNNER=xcodebuild\nexport RUNNER\nfocusflow_screenshot_resolve_runner")
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "xcodebuild")
    }

    func testReadmePublishingReadsContractCopiesAndResizesArtifacts() throws {
        let contractRows = try loadContractRows(from: contractURL)
        let sandboxURL = try makeSandboxRepo()
        defer { try? FileManager.default.removeItem(at: sandboxURL) }

        let sandboxContractURL = sandboxURL
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent("readme-screenshot-contract.tsv")
        try FileManager.default.copyItem(at: contractURL, to: sandboxContractURL)

        let runID = "task1-readme-publish"
        for row in contractRows {
            let sourceURL = sandboxURL
                .appendingPathComponent("Artifacts", isDirectory: true)
                .appendingPathComponent("review", isDirectory: true)
                .appendingPathComponent(runID, isDirectory: true)
                .appendingPathComponent(row.appearance, isDirectory: true)
                .appendingPathComponent("\(row.flowID).png")
            try writePNG(at: sourceURL, width: row.sourceWidth, height: row.sourceHeight)
        }

        let result = try runHelperCommand(
            "focusflow_publish_readme_screenshots \(shellQuote(sandboxURL.path)) \(shellQuote(runID))"
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        for row in contractRows {
            let outputURL = sandboxURL.appendingPathComponent(row.outputPath)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputURL.path),
                "Missing published screenshot at \(row.outputPath)"
            )
            let dimensions = try readImageDimensions(at: outputURL)
            XCTAssertEqual(dimensions, ImageDimensions(width: row.outputWidth, height: row.outputHeight))
        }
    }

    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var helperScriptURL: URL {
        repoRootURL
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("screenshot-automation.sh")
    }

    private var contractURL: URL {
        repoRootURL
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent("readme-screenshot-contract.tsv")
    }

    private func loadContractRows(from url: URL) throws -> [ContractRow] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents
            .split(whereSeparator: \ .isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else { return [] }

        return try lines.dropFirst().map { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 7,
                  let sourceWidth = Int(columns[2]),
                  let sourceHeight = Int(columns[3]),
                  let outputWidth = Int(columns[5]),
                  let outputHeight = Int(columns[6]) else {
                throw TestError.invalidContractRow(line)
            }

            return ContractRow(
                flowID: columns[0],
                appearance: columns[1],
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                outputPath: columns[4],
                outputWidth: outputWidth,
                outputHeight: outputHeight
            )
        }
    }

    private func runHelperCommand(_ command: String) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "set -eu\n. \(shellQuote(helperScriptURL.path))\n\(command)"
        ]
        process.currentDirectoryURL = repoRootURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    private func makeSandboxRepo() throws -> URL {
        let sandboxURL = repoRootURL
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("screenshot-automation-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(
            at: sandboxURL.appendingPathComponent("Scripts", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )

        return sandboxURL
    }

    private func writePNG(at url: URL, width: Int, height: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.imageWriteFailed("Unable to create CGContext for \(url.path)")
        }

        context.setFillColor(CGColor(red: 0.16, green: 0.22, blue: 0.34, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw TestError.imageWriteFailed("Unable to create CGImage for \(url.path)")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw TestError.imageWriteFailed("Unable to create PNG destination for \(url.path)")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.imageWriteFailed("Unable to finalize PNG for \(url.path)")
        }
    }

    private func readImageDimensions(at url: URL) throws -> ImageDimensions {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw TestError.imageReadFailed("Unable to read image dimensions for \(url.path)")
        }

        return ImageDimensions(width: width, height: height)
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
