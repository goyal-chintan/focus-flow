import Testing
import Foundation
@testable import FocusFlow

@Suite("InterventionSuppressionWindow")
struct InterventionSuppressionWindowTests {

    @Test("offDuty suppression lasts 90 minutes")
    func offDutySuppression() {
        let window = InterventionSuppressionWindow(reason: .offDuty, suppressedAt: Date())
        #expect(window.reason.suppressionDuration == 90 * 60)
        #expect(window.isActive == true)
    }

    @Test("doneForNow suppression lasts 60 minutes")
    func doneForNowSuppression() {
        let window = InterventionSuppressionWindow(reason: .doneForNow, suppressedAt: Date())
        #expect(window.reason.suppressionDuration == 60 * 60)
        #expect(window.isActive == true)
    }

    @Test("realBreak suppression lasts 45 minutes")
    func realBreakSuppression() {
        let window = InterventionSuppressionWindow(reason: .realBreak, suppressedAt: Date())
        #expect(window.reason.suppressionDuration == 45 * 60)
        #expect(window.isActive == true)
    }

    @Test("expired window is not active")
    func expiredWindowNotActive() {
        // Create window that started 2 hours ago
        let pastDate = Date().addingTimeInterval(-2 * 3600)
        let window = InterventionSuppressionWindow(reason: .offDuty, suppressedAt: pastDate)
        #expect(window.isActive == false)
    }

    @Test("fresh window is active")
    func freshWindowActive() {
        let window = InterventionSuppressionWindow(reason: .meeting, suppressedAt: Date())
        #expect(window.isActive == true)
        #expect(window.expiresAt > Date())
    }
}
