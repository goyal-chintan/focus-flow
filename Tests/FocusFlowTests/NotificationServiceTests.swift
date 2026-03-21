import XCTest
import UserNotifications
@testable import FocusFlow

final class NotificationServiceTests: XCTestCase {
    func testAuthorizationStateMapsAuthorizedToAuthorized() {
        XCTAssertEqual(
            NotificationService.authorizationState(for: .authorized),
            .authorized
        )
    }

    func testAuthorizationStateMapsProvisionalToAuthorized() {
        XCTAssertEqual(
            NotificationService.authorizationState(for: .provisional),
            .authorized
        )
    }

    func testAuthorizationStateMapsDeniedToDenied() {
        XCTAssertEqual(
            NotificationService.authorizationState(for: .denied),
            .denied
        )
    }

    func testAuthorizationStateMapsNotDeterminedToNotDetermined() {
        XCTAssertEqual(
            NotificationService.authorizationState(for: .notDetermined),
            .notDetermined
        )
    }
}
