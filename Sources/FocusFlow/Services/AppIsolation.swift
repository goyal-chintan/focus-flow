import Foundation

/// Where FocusFlow keeps its settings and files: `UserDefaults.standard` and
/// ~/Library/Application Support/FocusFlow.
///
/// A debug run with `FOCUSFLOW_DEBUG_FRESH_STORE=1` (an empty in-memory store) gets a throwaway
/// settings domain and folder instead. Before 18 Nov 2026 only the store was swapped: a trial run
/// still appended to the real coach journal, reset the coach's learning (`focusflow.coachBandit.v1`)
/// and left a crash checkpoint for the real app. FocusFlow's own settings and files must come from
/// here (`AppIsolationTests` fails on a direct use). Not covered: what macOS saves for the app
/// itself (window frames, saved window state), and system changes a trial makes on purpose
/// (blocking edits /etc/hosts; synced tasks write to Reminders).
enum AppIsolation {
    /// True for a debug run on the empty store. Always false in release builds.
    static let isIsolated: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_FRESH_STORE"] == "1"
        #else
        false
        #endif
    }()

    private static let isolatedSuiteName = "com.focusflow.app.isolated"

    /// The settings every part of the app reads and writes. Isolated: its own domain, emptied
    /// at launch, so each trial run starts like a first run.
    /// UserDefaults is thread-safe; Swift cannot see that.
    nonisolated(unsafe) static let defaults: UserDefaults = makeDefaults(isolated: isIsolated)

    static func makeDefaults(isolated: Bool, suiteName: String = isolatedSuiteName) -> UserDefaults {
        guard isolated, let suite = UserDefaults(suiteName: suiteName) else { return .standard }
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }

    /// FocusFlow's folder (store, coach journal, blocking helper and log). Isolated: a new
    /// temporary folder for this run.
    static let supportDirectory: URL = {
        let directory = makeSupportDirectory(isolated: isIsolated, processID: ProcessInfo.processInfo.processIdentifier)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func makeSupportDirectory(isolated: Bool, processID: Int32) -> URL {
        if isolated {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("FocusFlow-isolated-\(processID)", isDirectory: true)
        }
        return (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("FocusFlow", isDirectory: true)
    }
}
