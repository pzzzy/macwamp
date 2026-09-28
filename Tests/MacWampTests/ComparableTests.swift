import XCTest
@testable import MacWamp

final class ComparableTests: XCTestCase {
    func testClampedKeepsValuesInsideBounds() {
        XCTAssertEqual(12.clamped(0, 20), 12)
    }

    func testClampedMovesValuesBelowAndAboveBoundsToNearestBound() {
        XCTAssertEqual((-4).clamped(0, 20), 0)
        XCTAssertEqual(24.clamped(0, 20), 20)
    }
}
