import XCTest
@testable import Bucky

final class LauncherPinnedBorderPolicyTests: XCTestCase {
    @available(macOS 26.0, *)
    func testPinnedWindowUsesBolderBorderWithoutChangingLayout() {
        XCTAssertGreaterThan(
            LauncherPinnedBorderPolicy.lineWidth(isPinned: true),
            LauncherPinnedBorderPolicy.lineWidth(isPinned: false)
        )
        XCTAssertEqual(LauncherPinnedBorderPolicy.lineWidth(isPinned: false), 1)
        XCTAssertEqual(LauncherPinnedBorderPolicy.lineWidth(isPinned: true), 3)
    }
}
