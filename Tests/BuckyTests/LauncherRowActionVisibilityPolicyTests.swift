import XCTest
@testable import Bucky

final class LauncherRowActionVisibilityPolicyTests: XCTestCase {
    func testActionIsHiddenWhenRowIsNeitherSelectedNorHovered() {
        let policy = LauncherRowActionVisibilityPolicy(
            hasAction: true,
            isSelected: false,
            isHovered: false
        )

        XCTAssertFalse(policy.isVisible)
        XCTAssertFalse(policy.allowsHitTesting)
    }

    func testActionIsVisibleForSelectedOrHoveredActionableRows() {
        XCTAssertTrue(
            LauncherRowActionVisibilityPolicy(
                hasAction: true,
                isSelected: true,
                isHovered: false
            ).isVisible
        )
        XCTAssertTrue(
            LauncherRowActionVisibilityPolicy(
                hasAction: true,
                isSelected: false,
                isHovered: true
            ).isVisible
        )
    }

    func testRowsWithoutSecondaryActionStayHiddenEvenWhenSelectedOrHovered() {
        let policy = LauncherRowActionVisibilityPolicy(
            hasAction: false,
            isSelected: true,
            isHovered: true
        )

        XCTAssertFalse(policy.isVisible)
        XCTAssertFalse(policy.allowsHitTesting)
    }
}
