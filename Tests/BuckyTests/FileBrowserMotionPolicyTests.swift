import XCTest
@testable import Bucky

final class FileBrowserMotionPolicyTests: XCTestCase {
    func testWobbleUsesGentleDisplacement() {
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.wobbleAmplitude, 2.5)
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.wobbleOscillations, 1.25)
    }

    func testNavigationRowsDoNotHoldOnAnEmptyPause() {
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.rowSwapOutgoingDelayNanoseconds, 200_000_000)
        XCTAssertGreaterThanOrEqual(FileBrowserMotionPolicy.rowSwapIncomingSettleDelayNanoseconds, 260_000_000)
    }
}
