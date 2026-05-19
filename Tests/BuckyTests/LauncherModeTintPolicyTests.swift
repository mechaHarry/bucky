import XCTest
@testable import Bucky

final class LauncherModeTintPolicyTests: XCTestCase {
    func testModeTintPaletteUsesBrightStoneColors() {
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).activeHex, 0x266EF6)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .calculator).activeHex, 0xFFD300)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .dictionary).activeHex, 0xE429F2)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).activeHex, 0xFF0130)
    }

    func testModeTintPaletteUsesDarkPanelCompanions() {
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).panelHex, 0x08578A)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .calculator).panelHex, 0xFFC239)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .dictionary).panelHex, 0xBF00FF)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).panelHex, 0xC60404)
    }

    func testInactiveOrbGlassTintIsSofterThanIconTint() {
        XCTAssertEqual(ModeSwitcherTintPolicy.inactiveOrbGlassTintOpacity, 0.34)
        XCTAssertEqual(ModeSwitcherTintPolicy.inactiveOrbIconOpacity, 0.94)
        XCTAssertLessThan(
            ModeSwitcherTintPolicy.inactiveOrbGlassTintOpacity,
            ModeSwitcherTintPolicy.inactiveOrbIconOpacity
        )
    }

    func testModeTintIsWiredToPillsAndPanelBackdrops() throws {
        let modeSwitcher = try source(named: "Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(modeSwitcher.contains("LauncherModeTintPolicy.activeColor(for: mode)"))
        XCTAssertTrue(modeSwitcher.contains("LauncherModeTintPolicy.inactiveOrbIconColor(for: mode)"))
        XCTAssertTrue(modeSwitcher.contains("TextInputPillGlassSurface(tint:"))
        XCTAssertTrue(modeSwitcher.contains(".tint(LauncherModeTintPolicy.inactiveOrbColor(for: mode))"))
        XCTAssertTrue(modeSwitcher.contains("ModeSwitcherTintPolicy.activePillTintOpacity"))
        XCTAssertTrue(launcher.contains("LauncherModeTintPolicy.panelColor(for: model.mode)"))
        XCTAssertTrue(launcher.contains("LauncherVisualStyle.panelModeTintOpacity"))
        XCTAssertTrue(launcher.contains("LauncherVisualStyle.windowModeTintOpacity"))
    }

    func testLauncherBackdropDoesNotAddOuterWindowShadow() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(launcher.contains("private var windowBackdrop: some View"))
        XCTAssertFalse(launcher.contains(".shadow(color: .black.opacity(0.22), radius: 30, x: 0, y: 20)"))
    }

    func testModeTintIsWiredToSelectionHighlightsAndFileIndicator() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        let resultList = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")
        let fileBrowser = try source(named: "Sources/Bucky/UI/SwiftUI/FileBrowserView.swift")

        XCTAssertTrue(launcher.contains("selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)"))
        XCTAssertTrue(launcher.contains("FileBrowserView(\n                model: model.fileBrowserModel,\n                selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)\n            )"))
        XCTAssertTrue(resultList.contains("let selectionTint: Color"))
        XCTAssertTrue(resultList.contains("tint: selectionTint,"))
        XCTAssertTrue(resultList.contains("selectionTint.opacity(0.42)"))
        XCTAssertTrue(fileBrowser.contains("let selectionTint: Color"))
        XCTAssertTrue(fileBrowser.contains(".fill(selectionTint)"))
        XCTAssertTrue(fileBrowser.contains(".shadow(color: selectionTint.opacity(0.5), radius: 5)"))
    }

    func testPillTooltipsIncludeCommandShortcutNumbers() throws {
        let modeSwitcher = try source(named: "Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")

        XCTAssertTrue(modeSwitcher.contains(".help(helpText(for: mode))"))
        XCTAssertTrue(modeSwitcher.contains("Command+1"))
        XCTAssertTrue(modeSwitcher.contains("Command+2"))
        XCTAssertTrue(modeSwitcher.contains("Command+3"))
        XCTAssertTrue(modeSwitcher.contains("Command+4"))
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
