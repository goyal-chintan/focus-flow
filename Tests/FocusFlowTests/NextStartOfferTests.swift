import XCTest
@testable import FocusFlow

/// The block-end window offered "Start 5m" right above "Break 5m"; a click meant for the break
/// started a 5-minute focus block six times (30 Oct–6 Nov 2026).
final class NextStartOfferTests: XCTestCase {
    func testAfterABlockThereIsNoSmallerStart() {
        XCTAssertNil(NextStartOffer.smallerMinutes(after: .block, regular: 25, coachAsk: nil))
        XCTAssertNil(NextStartOffer.smallerMinutes(after: .block, regular: 25, coachAsk: 5))
        XCTAssertNil(NextStartOffer.smallerMinutes(after: .block, regular: 25, coachAsk: 15))
    }

    func testAfterABreakOnlyTheCoachsLearnedSmallerAsk() {
        XCTAssertNil(NextStartOffer.smallerMinutes(after: .breakEnded, regular: 25, coachAsk: nil), "No fixed 5-minute fallback")
        XCTAssertNil(NextStartOffer.smallerMinutes(after: .breakEnded, regular: 25, coachAsk: 25))
        XCTAssertNil(NextStartOffer.smallerMinutes(after: .breakEnded, regular: 25, coachAsk: 50))
        XCTAssertEqual(NextStartOffer.smallerMinutes(after: .breakEnded, regular: 25, coachAsk: 15), 15)
    }
}
