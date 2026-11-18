import XCTest
@testable import FocusFlow

/// A trial run on the empty store must not touch the real settings or folder (18 Nov 2026: one
/// reset the coach's learning and wrote to the real coach journal).
final class AppIsolationTests: XCTestCase {
    @MainActor
    func testTheAppUsesTheRealSettingsAndFolderOutsideATrialRun() {
        XCTAssertFalse(AppIsolation.isIsolated, "Tests never set FOCUSFLOW_DEBUG_FRESH_STORE")
        XCTAssertTrue(AppIsolation.defaults === UserDefaults.standard)
        XCTAssertTrue(AppIsolation.supportDirectory.path.hasSuffix("Application Support/FocusFlow"))
        XCTAssertEqual(CoachJournal.defaultURL.deletingLastPathComponent(), AppIsolation.supportDirectory)
    }

    func testATrialRunWritesToItsOwnSettingsThatStartEmpty() {
        let name = TestDefaults.make("isolation").name
        addTeardownBlock { TestDefaults.remove(name) }
        let key = "FocusFlowTests.isolation.\(UUID().uuidString)"

        let trial = AppIsolation.makeDefaults(isolated: true, suiteName: name)
        XCTAssertFalse(trial === UserDefaults.standard)
        trial.set("trial", forKey: key)
        XCTAssertEqual(trial.string(forKey: key), "trial")
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "The trial's write stays out of the real settings")
        XCTAssertNil(AppIsolation.makeDefaults(isolated: true, suiteName: name).object(forKey: key), "Each trial run starts empty")
    }

    func testATrialRunKeepsItsFilesInATemporaryFolder() {
        let folder = AppIsolation.makeSupportDirectory(isolated: true, processID: 4242)
        XCTAssertEqual(folder.lastPathComponent, "FocusFlow-isolated-4242")
        XCTAssertTrue(folder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertNotEqual(folder, AppIsolation.makeSupportDirectory(isolated: false, processID: 4242))
    }

    /// Keeps it that way: the app's code reaches its settings and folder only through
    /// `AppIsolation`, so a new direct use cannot quietly write to the real ones in a trial run.
    func testNoCodeReachesTheRealSettingsOrFolderDirectly() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FocusFlow")
        let forbidden: [(pattern: String, why: String)] = [
            (#"UserDefaults\.standard"#, "use AppIsolation.defaults"),
            (#"UserDefaults = \.standard"#, "default to AppIsolation.defaults"),
            (#"defaults: \.standard"#, "pass AppIsolation.defaults"),
            (#"@AppStorage\((?![^)]*store:)"#, "add store: AppIsolation.defaults"),
            (#"applicationSupportDirectory"#, "use AppIsolation.supportDirectory"),
            (#"NSHomeDirectory\(\)"#, "use AppIsolation.supportDirectory"),
        ]
        let regexes = try forbidden.map { (try NSRegularExpression(pattern: $0.pattern), $0.why) }
        var hits: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "AppIsolation.swift" } ?? []
        XCTAssertFalse(files.isEmpty, "Found no sources at \(sources.path)")
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (number, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let range = NSRange(line.startIndex..., in: line)
                for (regex, why) in regexes where regex.firstMatch(in: line, range: range) != nil {
                    hits.append("\(file.lastPathComponent):\(number + 1): \(why)")
                }
            }
        }
        XCTAssertEqual(hits, [], "Settings or files outside AppIsolation:\n" + hits.joined(separator: "\n"))
    }
}
