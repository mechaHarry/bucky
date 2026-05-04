import XCTest
@testable import Bucky

final class LauncherRowActionVisibilityPolicyTests: XCTestCase {
    func testActionableRowsKeepActionsVisibleWithoutPointerState() {
        let policy = LauncherRowActionVisibilityPolicy(
            hasAction: true
        )

        XCTAssertTrue(policy.isVisible)
        XCTAssertTrue(policy.allowsHitTesting)
    }

    func testRowsWithoutSecondaryActionStayHidden() {
        let policy = LauncherRowActionVisibilityPolicy(
            hasAction: false
        )

        XCTAssertFalse(policy.isVisible)
        XCTAssertFalse(policy.allowsHitTesting)
    }
}
