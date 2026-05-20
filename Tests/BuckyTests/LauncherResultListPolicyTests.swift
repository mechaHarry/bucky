import XCTest
@testable import Bucky

final class LauncherResultListPolicyTests: XCTestCase {
    func testSharedResultListUsesAppsSpacingAndMainPanelAlignment() {
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowSpacing, 14)
        XCTAssertEqual(LauncherResultListLayoutPolicy.contentMargin, 0)
        XCTAssertGreaterThanOrEqual(LauncherResultListLayoutPolicy.horizontalShadowBleed, 18)
        XCTAssertGreaterThanOrEqual(LauncherResultListLayoutPolicy.verticalShadowClearance, 18)
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowCornerRadius, 18)
    }

    func testSharedResultListKeepsScrollContentOutOfHeaderWhileGivingShadowsAir() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertFalse(source.contains(".scrollClipDisabled(true)"))
        XCTAssertTrue(source.contains(".contentMargins(.horizontal, LauncherResultListLayoutPolicy.horizontalShadowBleed"))
        XCTAssertTrue(source.contains(".contentMargins(.vertical, LauncherResultListLayoutPolicy.verticalShadowClearance"))
        XCTAssertTrue(source.contains(".padding(.horizontal, -LauncherResultListLayoutPolicy.horizontalShadowBleed)"))
        XCTAssertFalse(source.contains("shadowClearance"))
    }

    func testSharedResultListDoesNotUseAetherEdgeTreatment() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertFalse(source.contains("LauncherAetherEdgePolicy"))
        XCTAssertFalse(source.contains("launcherAetherEdgeTreatment()"))
        XCTAssertFalse(source.contains("LauncherAetherEdgeOverlay"))
        XCTAssertFalse(source.contains("appliesAetherEdgeTreatment"))
    }

    func testSharedResultRowsAreIndependentGlassObjects() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertTrue(source.contains("GlassEffectContainer(spacing: 0)"))
        XCTAssertTrue(source.contains(".glassEffect("))
        XCTAssertTrue(source.contains(".glassEffectID(LauncherResultRowGlassEffectID.selection"))
        XCTAssertTrue(source.contains(".glassEffectTransition(.matchedGeometry)"))
        XCTAssertTrue(source.contains(".shadow("))
        XCTAssertTrue(source.contains("radius: isSelected ? 13 : 9"))
        XCTAssertTrue(source.contains("x: 0, y: 2"))
        XCTAssertTrue(source.contains("isSelected ? 0.18 : 0.10"))
    }

    func testSharedResultListAnimationKeepsRowsFastButVisible() {
        XCTAssertLessThanOrEqual(LauncherResultListLayoutPolicy.rowSelectionAnimationSeconds, 0.18)
        XCTAssertLessThanOrEqual(LauncherResultListLayoutPolicy.rowReconstructionAnimationSeconds, 0.22)
    }

    private func source(named path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
