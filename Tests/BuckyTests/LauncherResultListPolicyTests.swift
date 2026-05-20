import XCTest
@testable import Bucky

final class LauncherResultListPolicyTests: XCTestCase {
    func testSharedResultListUsesAppsSpacingAndMainPanelAlignment() {
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowSpacing, 10)
        XCTAssertEqual(LauncherResultListLayoutPolicy.contentMargin, 0)
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowCornerRadius, 18)
    }

    func testSharedResultListUsesAetherEdgeTreatment() throws {
        XCTAssertEqual(LauncherAetherEdgePolicy.edgeBandHeight, 28)
        XCTAssertEqual(LauncherAetherEdgePolicy.edgeGlassOpacity, 0.52)
        XCTAssertEqual(LauncherAetherEdgePolicy.edgeFadeStop, 0.72)

        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertTrue(source.contains("launcherAetherEdgeTreatment()"))
        XCTAssertTrue(source.contains("LauncherAetherEdgeOverlay(edge: .top)"))
        XCTAssertTrue(source.contains("LauncherAetherEdgeOverlay(edge: .bottom)"))
    }

    func testSharedResultRowsAvoidShadowCastingGlassSurfaces() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertFalse(source.contains("GlassEffectContainer(spacing: 0)"))
        XCTAssertFalse(source.contains(".glassEffect("))
        XCTAssertFalse(source.contains(".shadow("))
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
