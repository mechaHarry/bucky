import XCTest
@testable import Bucky

final class LauncherResultListPolicyTests: XCTestCase {
    func testSharedResultListUsesAppsSpacingAndMainPanelAlignment() {
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowSpacing, 14)
        XCTAssertEqual(LauncherResultListLayoutPolicy.contentMargin, 12)
        XCTAssertEqual(LauncherResultListLayoutPolicy.horizontalShadowBleed, LauncherResultListLayoutPolicy.contentMargin)
        XCTAssertGreaterThanOrEqual(LauncherResultListLayoutPolicy.verticalShadowClearance, 18)
        XCTAssertGreaterThanOrEqual(LauncherResultListLayoutPolicy.verticalEdgeFadeLength, 24)
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowCornerRadius, 18)
    }

    func testSharedResultListKeepsHorizontalShadowBleedAlignedToContentMargin() {
        XCTAssertEqual(
            LauncherResultListLayoutPolicy.horizontalShadowBleed,
            LauncherResultListLayoutPolicy.contentMargin
        )
    }

    func testSharedResultListLeavesRoomForVerticalFadeAndShadows() {
        XCTAssertGreaterThan(
            LauncherResultListLayoutPolicy.verticalEdgeFadeLength,
            LauncherResultListLayoutPolicy.contentMargin
        )
        XCTAssertGreaterThanOrEqual(
            LauncherResultListLayoutPolicy.verticalShadowClearance,
            LauncherResultListLayoutPolicy.contentMargin
        )
    }

    func testSharedResultRowsUseBalancedVisibleRimAroundFullShape() {
        XCTAssertGreaterThanOrEqual(LauncherResultListVisualStyle.unselectedRimOpacity, 0.28)
        XCTAssertGreaterThanOrEqual(LauncherResultListVisualStyle.selectionRimOpacity, 0.40)
        XCTAssertGreaterThanOrEqual(LauncherResultListVisualStyle.rowRimLineWidth(isSelected: false), 1.10)
        XCTAssertGreaterThanOrEqual(LauncherResultListVisualStyle.rowRimLineWidth(isSelected: true), 1.20)
    }

    func testSharedResultListAnimationKeepsRowsFastButVisible() {
        XCTAssertLessThanOrEqual(LauncherResultListLayoutPolicy.rowSelectionAnimationSeconds, 0.10)
        XCTAssertLessThanOrEqual(LauncherResultListLayoutPolicy.rowReconstructionAnimationSeconds, 0.10)
    }
}
