import XCTest
@testable import Bucky

final class LauncherResultListPolicyTests: XCTestCase {
    func testSharedResultListUsesAppsSpacingAndMainPanelAlignment() {
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowSpacing, 14)
        XCTAssertEqual(LauncherResultListLayoutPolicy.contentMargin, 0)
        XCTAssertGreaterThanOrEqual(LauncherResultListLayoutPolicy.horizontalShadowBleed, 18)
        XCTAssertGreaterThanOrEqual(LauncherResultListLayoutPolicy.verticalShadowClearance, 18)
        XCTAssertGreaterThanOrEqual(LauncherResultListLayoutPolicy.verticalEdgeFadeLength, 24)
        XCTAssertEqual(LauncherResultListLayoutPolicy.rowCornerRadius, 18)
    }

    func testSharedResultListKeepsScrollContentOutOfHeaderWhileGivingShadowsAir() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertFalse(source.contains(".scrollClipDisabled(true)"))
        XCTAssertTrue(source.contains(".contentMargins(.horizontal, LauncherResultListLayoutPolicy.horizontalShadowBleed"))
        XCTAssertTrue(source.contains(".contentMargins(.vertical, LauncherResultListLayoutPolicy.verticalShadowClearance"))
        XCTAssertFalse(source.contains(".padding(.horizontal, -LauncherResultListLayoutPolicy.horizontalShadowBleed)"))
        XCTAssertFalse(source.contains("shadowClearance"))
    }

    func testSharedResultListUsesSoftVerticalEdgeMaskInsteadOfHardCut() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertFalse(source.contains(".mask(alignment: .center)"))
        XCTAssertFalse(source.contains("resultListVerticalEdgeMask"))
        XCTAssertFalse(source.contains("resultListVerticalEdgeFog"))
        XCTAssertFalse(source.contains("resultListVerticalEdgeMaterialFog"))
    }

    func testResultsPaneDoesNotUseEdgeVeil() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(source.contains("ZStack {\n            resultsPaneBackdrop"))
        XCTAssertTrue(source.contains(".clipShape(resultsPaneShape)"))
        XCTAssertFalse(source.contains("resultsPaneEdgeVeil"))
        XCTAssertFalse(source.contains("resultsPaneEdgeMaterialVeil"))
        XCTAssertFalse(source.contains("resultsPaneEdgeGradientVeil"))
        XCTAssertFalse(source.contains(".fill(.regularMaterial)\n            .mask"))
    }

    func testResultsPaneClipsRowsAtPaneBoundaryNotInsetBounds() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertFalse(source.contains("results\n                .padding(LauncherVisualStyle.resultsPaneContentInset)"))
        XCTAssertTrue(source.contains("results\n                .frame(maxWidth: .infinity, maxHeight: .infinity)\n                .clipShape(resultsPaneShape)"))
    }

    func testSharedResultListDoesNotUseAetherEdgeTreatment() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertFalse(source.contains("LauncherAetherEdgePolicy"))
        XCTAssertFalse(source.contains("launcherAetherEdgeTreatment()"))
        XCTAssertFalse(source.contains("LauncherAetherEdgeOverlay"))
        XCTAssertFalse(source.contains("appliesAetherEdgeTreatment"))
    }

    func testSharedResultRowsAvoidPerRowGlassAndShadows() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertFalse(source.contains("GlassEffectContainer(spacing: 0)"))
        XCTAssertFalse(source.contains(".glassEffect("))
        XCTAssertFalse(source.contains("LauncherResultRowGlassEffectID"))
        XCTAssertFalse(source.contains(".shadow("))
        XCTAssertTrue(source.contains(".fill(LauncherResultListVisualStyle.rowFill.opacity(0.32))"))
        XCTAssertTrue(source.contains(".fill(tint.opacity(opacity))"))
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
