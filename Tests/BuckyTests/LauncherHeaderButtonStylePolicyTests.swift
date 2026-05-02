import XCTest
@testable import Bucky

final class LauncherHeaderButtonStylePolicyTests: XCTestCase {
    func testActiveHeaderButtonUsesProminentAccentGlassStyle() {
        let policy = LauncherHeaderButtonStylePolicy(isActive: true)

        XCTAssertEqual(policy.style, .prominentAccentGlass)
    }

    func testInactiveHeaderButtonUsesStockGlassStyle() {
        let policy = LauncherHeaderButtonStylePolicy(isActive: false)

        XCTAssertEqual(policy.style, .stockGlass)
    }
}
