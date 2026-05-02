import XCTest
@testable import Bucky

final class LauncherHeaderButtonStylePolicyTests: XCTestCase {
    func testActiveHeaderButtonUsesAccentGlassTint() {
        let policy = LauncherHeaderButtonStylePolicy(isActive: true)

        XCTAssertTrue(policy.usesAccentGlassTint)
    }

    func testInactiveHeaderButtonUsesStockGlassStyle() {
        let policy = LauncherHeaderButtonStylePolicy(isActive: false)

        XCTAssertFalse(policy.usesAccentGlassTint)
    }
}
