import XCTest
@testable import Bucky

final class FileBrowserMotionPolicyTests: XCTestCase {
    func testWobbleUsesGentleDisplacement() {
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.wobbleAmplitude, 2.5)
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.wobbleOscillations, 1.25)
    }

    func testListReconstructionUsesAppsStyleShortAnimation() {
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.listReconstructionAnimationSeconds, 0.22)
    }
}
