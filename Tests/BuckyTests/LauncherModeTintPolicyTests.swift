import XCTest
@testable import Bucky

final class LauncherModeTintPolicyTests: XCTestCase {
    func testModeTintPaletteUsesBrightStoneColors() {
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).activeHex, 0x266EF6)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .calculator).activeHex, 0xFFD300)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .dictionary).activeHex, 0xE429F2)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).activeHex, 0xFF0130)
    }

    func testCalculatorModeUsesContrastingIconInk() {
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).iconHex, 0x0B3D91)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .calculator).iconHex, 0x3A2B00)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .dictionary).iconHex, 0x6E1977)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).iconHex, 0x7A0018)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .applications).darkModeIconHex, 0x9CC7FF)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .calculator).darkModeIconHex, 0xFFF0A3)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .dictionary).darkModeIconHex, 0xF5B8FF)
        XCTAssertEqual(LauncherModeTintPolicy.tint(for: .files).darkModeIconHex, 0xFFA6B8)
        XCTAssertNotEqual(
            LauncherModeTintPolicy.tint(for: .applications).iconHex,
            LauncherModeTintPolicy.tint(for: .applications).activeHex
        )
        XCTAssertNotEqual(
            LauncherModeTintPolicy.tint(for: .calculator).iconHex,
            LauncherModeTintPolicy.tint(for: .calculator).activeHex
        )
        XCTAssertNotEqual(
            LauncherModeTintPolicy.tint(for: .dictionary).iconHex,
            LauncherModeTintPolicy.tint(for: .dictionary).activeHex
        )
        XCTAssertNotEqual(
            LauncherModeTintPolicy.tint(for: .files).iconHex,
            LauncherModeTintPolicy.tint(for: .files).activeHex
        )
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

    func testSelectionColorMatchesActiveColorForEachMode() {
        for mode in LauncherMode.ordered {
            XCTAssertEqual(
                LauncherModeTintPolicy.selectionColor(for: mode),
                LauncherModeTintPolicy.activeColor(for: mode)
            )
        }
    }

    func testIconColorUsesDarkVariantOnlyInDarkMode() {
        XCTAssertEqual(
            LauncherModeTintPolicy.iconColor(for: .calculator, colorScheme: .light),
            LauncherModeTintPolicy.iconColor(for: .calculator)
        )
        XCTAssertNotEqual(
            LauncherModeTintPolicy.iconColor(for: .calculator, colorScheme: .dark),
            LauncherModeTintPolicy.iconColor(for: .calculator, colorScheme: .light)
        )
    }
}
