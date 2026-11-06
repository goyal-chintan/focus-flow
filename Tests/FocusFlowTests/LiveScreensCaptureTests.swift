import XCTest
import SwiftUI
import SwiftData
@testable import FocusFlow

/// FOCUSFLOW_LIVE_STORE_COPY=<copy> FOCUSFLOW_CAPTURE_OUTPUT_DIR=<dir>: renders Goals, Today and
/// Insights from a real store copy, so a change can be looked at on real data without the app.
@MainActor
final class LiveScreensCaptureTests: XCTestCase {
    func testCaptureLiveScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["FOCUSFLOW_LIVE_STORE_COPY"], let out = env["FOCUSFLOW_CAPTURE_OUTPUT_DIR"] else {
            throw XCTSkip("Set FOCUSFLOW_LIVE_STORE_COPY and FOCUSFLOW_CAPTURE_OUTPUT_DIR")
        }
        let schema = FocusFlowSchema.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: URL(fileURLWithPath: path)))
        let context = container.mainContext
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<AppSettings>()).first)
        let vm = TimerViewModel(defaults: cleanDefaults("livescreens"))
        vm.configureForEvidence(modelContext: context, settings: settings)
        defer { AppUsageTracker.shared.stop() }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        let screens: [(String, AnyView, CGFloat)] = [
            ("goals", AnyView(GoalsView()), 1500),
            ("today", AnyView(TodayView()), 1600),
            ("insights", AnyView(InsightsView()), 2600),
        ]
        for (name, view, height) in screens {
            let hosted = view
                .environment(vm)
                .modelContainer(container)
                .environment(\.focusFlowEvidenceRendering, true)
                .frame(width: 800, height: height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
            let size = CGSize(width: 800, height: height)
            let host = NSHostingView(rootView: hosted)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            window.displayIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            host.layoutSubtreeIfNeeded()
            host.display()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            window.close()
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: out).appendingPathComponent("live_\(name).png"))
        }
    }
}
