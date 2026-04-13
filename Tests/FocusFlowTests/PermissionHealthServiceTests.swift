import XCTest
@testable import FocusFlow

@MainActor
final class PermissionHealthServiceTests: XCTestCase {
    func testRowsReturnStableFivePermissionOrder() {
        let service = PermissionHealthService(
            notificationStateProvider: { .authorized },
            calendarStatusProvider: { .authorized },
            remindersStatusProvider: { .authorized },
            screenRecordingAccessProvider: { true },
            installedAutomationTargetsProvider: { [] },
            automationStatusProvider: { _ in .ready }
        )

        let rows = service.rows(calendarIntegrationEnabled: false, remindersIntegrationEnabled: false)

        XCTAssertEqual(
            rows.map(\.title),
            ["Notifications", "Calendar", "Reminders", "Browser Automation", "Screen Recording"]
        )
    }

    func testBrowserAutomationRowNeedsActionWhenAnyInstalledBrowserIsBlocked() throws {
        let arc = try XCTUnwrap(
            BrowserDomainResolver.supportedAutomationTargets.first(where: { $0.displayName == "Arc" })
        )
        let chrome = try XCTUnwrap(
            BrowserDomainResolver.supportedAutomationTargets.first(where: { $0.displayName == "Chrome" })
        )
        let service = PermissionHealthService(
            notificationStateProvider: { .authorized },
            calendarStatusProvider: { .authorized },
            remindersStatusProvider: { .authorized },
            screenRecordingAccessProvider: { true },
            installedAutomationTargetsProvider: { [arc, chrome] },
            automationStatusProvider: { target in
                target.bundleIdentifier == arc.bundleIdentifier ? .ready : .needsAction
            }
        )

        let row = service.rows(calendarIntegrationEnabled: false, remindersIntegrationEnabled: false)[3]

        XCTAssertEqual(row.title, "Browser Automation")
        XCTAssertEqual(row.status, .needsAction)
        XCTAssertTrue(row.detailLines.contains("Arc: Ready"))
        XCTAssertTrue(row.detailLines.contains("Chrome: Needs action"))
    }

    func testBrowserAutomationRowIsUnavailableWithoutSupportedBrowsers() {
        let service = PermissionHealthService(
            notificationStateProvider: { .authorized },
            calendarStatusProvider: { .authorized },
            remindersStatusProvider: { .authorized },
            screenRecordingAccessProvider: { true },
            installedAutomationTargetsProvider: { [] },
            automationStatusProvider: { _ in .ready }
        )

        let row = service.rows(calendarIntegrationEnabled: false, remindersIntegrationEnabled: false)[3]

        XCTAssertEqual(row.status, .unavailable)
        XCTAssertTrue(row.message.contains("No supported browsers"))
    }

    func testBrowserAutomationRowCanRenderPendingStateWithoutLiveProbe() throws {
        let arc = try XCTUnwrap(
            BrowserDomainResolver.supportedAutomationTargets.first(where: { $0.displayName == "Arc" })
        )
        var probeCallCount = 0
        let service = PermissionHealthService(
            notificationStateProvider: { .authorized },
            calendarStatusProvider: { .authorized },
            remindersStatusProvider: { .authorized },
            screenRecordingAccessProvider: { true },
            installedAutomationTargetsProvider: { [arc] },
            automationStatusProvider: { _ in
                probeCallCount += 1
                return .ready
            }
        )

        let row = service.rows(
            calendarIntegrationEnabled: false,
            remindersIntegrationEnabled: false,
            automationProbeInProgress: true
        )[3]

        XCTAssertEqual(probeCallCount, 0)
        XCTAssertEqual(row.status, .notRequested)
        XCTAssertTrue(row.message.contains("Checking"))
        XCTAssertEqual(row.detailLines, ["Arc: Checking…"])
    }

    func testCalendarRowExplainsWhenPermissionIsGrantedButIntegrationIsStillOff() {
        let service = PermissionHealthService(
            notificationStateProvider: { .authorized },
            calendarStatusProvider: { .authorized },
            remindersStatusProvider: { .authorized },
            screenRecordingAccessProvider: { true },
            installedAutomationTargetsProvider: { [] },
            automationStatusProvider: { _ in .ready }
        )

        let row = service.rows(calendarIntegrationEnabled: false, remindersIntegrationEnabled: false)[1]

        XCTAssertEqual(row.status, .ready)
        XCTAssertEqual(row.action, .openIntegrationsSection)
        XCTAssertTrue(row.message.contains("Turn on Record to Calendar in Integrations"))
    }

    func testBrowserAutomationProbeReturnsNotRequestedUnderXCTest() throws {
        let target = try XCTUnwrap(BrowserDomainResolver.supportedAutomationTargets.first)

        XCTAssertEqual(BrowserAutomationPermissionProbe.status(for: target), .notRequested)
    }
}
