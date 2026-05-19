import XCTest
@testable import Bucky

final class LauncherResultListPolicyTests: XCTestCase {
    func testSharedResultListUsesAppsSpacingAndMainPanelAlignment() {
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowSpacing, 10)
        XCTAssertEqual(LauncherResultListLayoutPolicy.contentMargin, 0)
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowCornerRadius, 18)
    }

    func testSharedResultRowsAvoidShadowCastingGlassSurfaces() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("GlassEffectContainer(spacing: 0)"))
        XCTAssertFalse(source.contains(".glassEffect("))
        XCTAssertFalse(source.contains(".shadow("))
    }

    func testSharedResultListAnimationKeepsRowsFastButVisible() {
        XCTAssertLessThanOrEqual(LauncherResultListLayoutPolicy.rowSelectionAnimationSeconds, 0.18)
        XCTAssertLessThanOrEqual(LauncherResultListLayoutPolicy.rowReconstructionAnimationSeconds, 0.22)
    }
}
