import XCTest
import SwiftUI
@testable import FocusFlow

/// Notch companion geometry and rendering (notch design).
final class NotchTests: XCTestCase {
    func testHardwareNotchIsFoundFromTheMenuBarAreas() {
        // 14" MacBook Pro: 1512 pt wide, notch ~ 185 pt, safe area 32 pt.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(screenFrame: screen, safeAreaTop: 32, leftAreaWidth: 663, rightAreaWidth: 664, menuBarHeight: 24)
        XCTAssertTrue(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notch, CGRect(x: 663, y: 950, width: 185, height: 32))
        XCTAssertEqual(geometry.compactFrame.width, 185 + 2 * NotchGeometry.wingWidth)
        XCTAssertEqual(geometry.compactFrame.maxY, screen.maxY, "Flush with the top edge")
        XCTAssertEqual(geometry.expandedFrame.midX, geometry.notch.midX, accuracy: 0.5, "Centred on the notch")
        XCTAssertEqual(geometry.expandedFrame.maxY, screen.maxY)
        XCTAssertEqual(geometry.expandedFrame.height, NotchGeometry.expandedSize.height + 32)
    }

    func testScreenWithoutANotchGetsAVirtualOneOnTheTopEdge() {
        let screen = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry(screenFrame: screen, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, menuBarHeight: 24)
        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notch.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(geometry.notch.height, 24)
        XCTAssertEqual(geometry.notch.maxY, screen.maxY)
    }

    func testNotchShapeIsFlushAtTheTopAndClosed() {
        let rect = CGRect(x: 0, y: 0, width: 330, height: 32)
        let path = NotchShape(earRadius: 8, bottomRadius: 11).path(in: rect)
        XCTAssertEqual(path.boundingRect.minY, 0, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.width, 330, accuracy: 0.01, "Ears reach the full width at the top edge")
        XCTAssertTrue(path.contains(CGPoint(x: 165, y: 16)))
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 30)), "Below the ear is outside (the menu bar shows through)")
    }

    // MARK: Renders (FOCUSFLOW_CAPTURE_OUTPUT_DIR/notch)

    @MainActor
    func testCaptureNotchStates() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_CAPTURE_OUTPUT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set FOCUSFLOW_CAPTURE_OUTPUT_DIR to capture")
        }
        let output = URL(fileURLWithPath: dir).appendingPathComponent("notch", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let lever = DailyLever(id: UUID(), goalTitle: "Interview-ready by 28 Nov", projectID: nil, action: "3 LeetCode questions",
                               reason: "need 2.6/day · 18 days left", status: .behind, urgency: 1)
        let base = NotchSnapshot(
            mode: .idle, time: "18:42", progress: 0.38, projectName: "Learning", projectColor: "purple",
            intent: "3 LeetCode questions", goalDone: 50 * 60, goalTarget: 2 * 3600, goalLabel: "Your own work",
            lever: lever, verdict: "3h 50m tracked · 50m on your #1 · 22% own work",
            coachHook: nil, quickResult: (UUID(), "LeetCode", 14, 60),
            tasks: DailyTaskStats(planned: 5, done: 2), nextTask: (UUID(), "Window functions practice set")
        )
        var attention = base
        attention.coachHook = "First block. Start small."
        attention.suggestedMinutes = 25
        attention.reminder = DailyReminderLine(text: "A year from now you may wish you had started today.", attribution: "Karen Lamb", isOwn: false)
        attention.nextTask = (UUID(), "LeetCode questions")
        attention.nextTaskCount = (1, 3)
        var receipt = base
        receipt.receipt = "+1 LeetCode · today 2 of 3 · goal 15 of 60"
        var focusing = base
        focusing.mode = .focusing
        var focusingNoTask = focusing
        focusingNoTask.nextTask = nil
        var paused = base
        paused.mode = .paused
        var overtime = base
        overtime.mode = .overtime
        overtime.time = "+03:12"
        var onBreak = base
        onBreak.mode = .onBreak(paused: false)
        onBreak.time = "04:21"

        let cases: [(String, NotchSnapshot, Bool)] = [
            ("compact_idle", base, false), ("compact_attention", attention, false), ("compact_focusing", focusing, false),
            ("compact_paused", paused, false), ("compact_overtime", overtime, false), ("compact_break", onBreak, false),
            ("expanded_idle", attention, true), ("expanded_receipt", receipt, true), ("expanded_focusing", focusing, true),
            ("expanded_focusing_no_task", focusingNoTask, true), ("expanded_overtime", overtime, true),
            ("expanded_break", onBreak, true),
        ]
        for (name, snapshot, expanded) in cases {
            let state = NotchState()
            state.notchSize = CGSize(width: 185, height: 32)
            state.expanded = expanded
            let canvas = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.75, green: 0.55, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.white.opacity(0.32)).frame(height: 32)
                HStack {
                    Text("  Safari   File   Edit   View").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("Wed 28 Oct  12:30  ").font(.system(size: 13, weight: .medium))
                }
                .frame(height: 32)
                .foregroundStyle(.black.opacity(0.8))
                NotchView(state: state, snapshot: snapshot)
            }
            .frame(width: 900, height: 330)
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = 2
            guard let image = renderer.cgImage else { XCTFail("render \(name)"); continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("\(name).png"))
        }
    }
}
