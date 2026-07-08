import XCTest
@testable import Bucky

final class LauncherModeTintPolicyTests: XCTestCase {
    func testModeTintPaletteUsesBrightStoneColors() {
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).activeHex, 0x266EF6)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).activeHex, 0xFF0130)
    }

    func testModeUsesContrastingIconInk() {
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).iconHex, 0x0B3D91)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).iconHex, 0x7A0018)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).darkModeIconHex, 0x9CC7FF)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).darkModeIconHex, 0xFFA6B8)
        XCTAssertNotEqual(
            LauncherModeTintPolicy.tint(for: .applications).iconHex,
            LauncherModeTintPolicy.tint(for: .applications).activeHex
        )
        XCTAssertNotEqual(
            LauncherModeTintPolicy.tint(for: .files).iconHex,
            LauncherModeTintPolicy.tint(for: .files).activeHex
        )
    }

    func testModeTintPaletteUsesDarkPanelCompanions() {
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).panelHex, 0x08578A)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).panelHex, 0xC60404)
    }

    func testAppsTintPreservesRouteSpecificNativeIdentity() {
        XCTAssertEqual(LauncherModeTintPolicy.appsTint(for: .applications(query: "")).activeHex, 0x266EF6)
        XCTAssertEqual(LauncherModeTintPolicy.appsTint(for: .calculator(expression: "1+1")).activeHex, 0xFFD300)
        XCTAssertEqual(LauncherModeTintPolicy.appsTint(for: .dictionary(term: "apple")).activeHex, 0xE429F2)
        XCTAssertEqual(LauncherModeTintPolicy.appsTint(for: .dictionary(term: "apple")).panelHex, 0xBF00FF)
        XCTAssertEqual(LauncherModeTintPolicy.appsTint(for: .dictionary(term: "apple")).iconHex, 0x6E1977)
    }

    func testInactiveOrbGlassTintIsSofterThanIconTint() {
        XCTAssertEqual(ModeSwitcherTintPolicy.inactiveOrbGlassTintOpacity, 0.34)
        XCTAssertEqual(ModeSwitcherTintPolicy.inactiveOrbIconOpacity, 0.94)
        XCTAssertLessThan(
            ModeSwitcherTintPolicy.inactiveOrbGlassTintOpacity,
            ModeSwitcherTintPolicy.inactiveOrbIconOpacity
        )
    }

    func testModeTintIsWiredToIndividualPillsWithoutHeaderGlass() throws {
        let modeSwitcher = try source(named: "Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(modeSwitcher.contains("LauncherModeTintPolicy.activeColor(for: mode)"))
        XCTAssertTrue(modeSwitcher.contains("LauncherModeTintPolicy.iconColor(for: mode, colorScheme: colorScheme)"))
        XCTAssertTrue(modeSwitcher.contains("LauncherModeTintPolicy.iconColor(for: .files, colorScheme: colorScheme)"))
        XCTAssertTrue(modeSwitcher.contains("LauncherModeTintPolicy.inactiveOrbIconColor(for: mode, colorScheme: colorScheme)"))
        XCTAssertTrue(modeSwitcher.contains("ModeControlBackground("))
        XCTAssertTrue(modeSwitcher.contains("fill: LauncherModeTintPolicy.inactiveOrbColor(for: mode)"))
        XCTAssertTrue(modeSwitcher.contains("tint: LauncherModeTintPolicy.activeColor(for: mode)"))
        XCTAssertFalse(modeSwitcher.contains("TextInputPillGlassSurface(tint:"))
        XCTAssertFalse(modeSwitcher.contains(".tint(LauncherModeTintPolicy.inactiveOrbColor(for: mode))"))
        XCTAssertFalse(launcher.contains("headerGlassBackdrop"))
        XCTAssertFalse(launcher.contains("headerGlassShape"))
        XCTAssertFalse(launcher.contains("LauncherVisualStyle.headerGlassTintOpacity"))
        XCTAssertFalse(launcher.contains(".background(windowBackdrop)"))
        XCTAssertFalse(launcher.contains("private var windowBackdrop: some View"))
        XCTAssertTrue(launcher.contains("private var resultsPaneBackdrop: some View"))
        XCTAssertTrue(launcher.contains("LauncherVisualStyle.resultsPaneModeTintOpacity"))
        XCTAssertTrue(launcher.contains("LauncherVisualStyle.resultsPaneRim"))
        XCTAssertTrue(launcher.contains("LauncherModeTintPolicy.panelColor(for: model.mode)"))
    }

    func testResultsPaneReturnsWithoutWrappingModeStones() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(launcher.contains("resultsPane"))
        XCTAssertTrue(launcher.contains("ZStack {\n            resultsPaneBackdrop"))
        XCTAssertFalse(launcher.contains("resultsPaneEdgeVeil"))
        XCTAssertFalse(launcher.contains("headerGlassBackdrop"))
        XCTAssertFalse(launcher.contains(".background {\n                header"))
    }

    func testLauncherBackdropDoesNotAddOuterWindowShadow() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertFalse(launcher.contains("private var windowBackdrop: some View"))
        XCTAssertFalse(launcher.contains(".clipShape(launcherOuterShape)"))
        XCTAssertFalse(launcher.contains("headerGlassBackdrop"))
        XCTAssertTrue(launcher.contains("static let windowCornerRadius: CGFloat = 30"))
        XCTAssertFalse(launcher.contains(".padding(LauncherWindowFramePolicy.shadowBleed)"))
        XCTAssertFalse(launcher.contains("resultsPane\n        .padding(10)"))
        XCTAssertFalse(launcher.contains(".shadow(color: .black.opacity(0.22), radius: 30, x: 0, y: 20)"))
        XCTAssertFalse(launcher.contains(".shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)"))
    }

    func testModeTintIsWiredToSelectionHighlightsAndFileIndicator() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        let resultList = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")
        let fileBrowser = try source(named: "Sources/Bucky/UI/SwiftUI/FileBrowserView.swift")

        XCTAssertTrue(launcher.contains("selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)"))
        XCTAssertTrue(launcher.contains("if let fileBrowserModel = model.activeFileBrowserModel"))
        XCTAssertTrue(launcher.contains("FileBrowserView(\n                    model: fileBrowserModel,\n                    selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)\n                )"))
        XCTAssertTrue(resultList.contains("let selectionTint: Color"))
        XCTAssertTrue(resultList.contains("tint: selectionTint,"))
        XCTAssertTrue(resultList.contains("selectionTint.opacity(0.42)"))
        XCTAssertTrue(fileBrowser.contains("let selectionTint: Color"))
        XCTAssertTrue(fileBrowser.contains(".fill(selectionTint)"))
        XCTAssertFalse(fileBrowser.contains(".shadow(color: selectionTint.opacity(0.5), radius: 5)"))
    }

    func testPillTooltipsIncludeCommandShortcutNumbers() throws {
        let modeSwitcher = try source(named: "Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")

        XCTAssertTrue(modeSwitcher.contains(".help(helpText(for: mode))"))
        XCTAssertTrue(modeSwitcher.contains("Command+1"))
        XCTAssertTrue(modeSwitcher.contains("Command+4"))
        XCTAssertFalse(modeSwitcher.contains("Command+2"))
        XCTAssertFalse(modeSwitcher.contains("Command+3"))
    }

    func testCalculatorModeStoneIconIsRemoved() throws {
        let modeSwitcher = try source(named: "Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")

        XCTAssertFalse(modeSwitcher.contains("return \"123.rectangle.fill\""))
        XCTAssertTrue(modeSwitcher.contains("function"))
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
