import XCTest
@testable import Bucky

final class LauncherButtonTintPolicyTests: XCTestCase {
    func testTintIsClearWhenButtonIsIdle() {
        let policy = LauncherButtonTintPolicy(isSelected: false, isHovered: false)

        XCTAssertEqual(policy.tintOpacity, 0)
    }

    func testHoverTintIsHalfOfSelectedTint() {
        let hovered = LauncherButtonTintPolicy(isSelected: false, isHovered: true)
        let selected = LauncherButtonTintPolicy(isSelected: true, isHovered: false)

        XCTAssertGreaterThan(hovered.tintOpacity, 0)
        XCTAssertEqual(hovered.tintOpacity * 2, selected.tintOpacity, accuracy: 0.001)
    }

    func testSelectedTintWinsOverHoverTint() {
        let policy = LauncherButtonTintPolicy(isSelected: true, isHovered: true)

        XCTAssertEqual(policy.tintOpacity, LauncherButtonTintPolicy.selectedTintOpacity)
    }
}
