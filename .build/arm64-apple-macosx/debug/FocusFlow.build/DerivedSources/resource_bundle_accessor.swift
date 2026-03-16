import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("FocusFlow_FocusFlow.bundle").path
        let buildPath = "/Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/session-editing-overtime/.build/arm64-apple-macosx/debug/FocusFlow_FocusFlow.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}