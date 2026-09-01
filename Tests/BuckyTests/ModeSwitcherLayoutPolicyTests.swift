import XCTest
@testable import Bucky

final class ModeSwitcherLayoutPolicyTests: XCTestCase {
    func testFilesPathWidthIsIndependentOfPathLength() {
        let shortPathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
            in: 520,
            path: "/Applications/Spotify.app"
        )
        let longPathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
            in: 520,
            path: "/Applications/ThousandEyes Security Endpoint.app/Contents/MacOS/ThousandEyes Security Endpoint"
        )

        XCTAssertEqual(shortPathWidth, longPathWidth)
        XCTAssertEqual(shortPathWidth, 274)
    }

    func testFilesPathWidthNeverGoesNegative() {
        XCTAssertEqual(ModeSwitcherLayoutPolicy.filesPathTextWidth(in: 120, path: "/very/long/path"), 0)
    }

    func testTextPillIconAndInputShareStableVerticalMetrics() {
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight,
            ModeSwitcherLayoutPolicy.activePillHeight - ModeSwitcherLayoutPolicy.activeTextPillVerticalInset * 2
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillInputHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillTextFieldHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertLessThanOrEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize,
            ModeSwitcherLayoutPolicy.activeTextPillIconWidth
        )
        XCTAssertLessThanOrEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize,
            ModeSwitcherLayoutPolicy.activeTextPillIconHeight
        )
        XCTAssertGreaterThan(
            ModeSwitcherLayoutPolicy.activeTextPillInputLeadingInset,
            ModeSwitcherLayoutPolicy.activeTextPillIconLeadingInset + ModeSwitcherLayoutPolicy.activeTextPillIconWidth
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress: false),
            ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset
        )
        XCTAssertGreaterThan(ModeSwitcherLayoutPolicy.activeTextPillVerticalInset, 0)
        XCTAssertLessThan(ModeSwitcherLayoutPolicy.activeTextPillControlHeight, ModeSwitcherLayoutPolicy.activePillHeight)
    }

    func testTextInputModesUseSharedTextPillLayout() {
        XCTAssertEqual(LauncherMode.ordered.filter(\.acceptsTextInput), [
            .applications,
            .calculator,
            .dictionary
        ])
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconLeadingInset,
            ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillInputLeadingInset,
            ModeSwitcherLayoutPolicy.activePillHeight + ModeSwitcherLayoutPolicy.activePillHeight / 12
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset,
            ModeSwitcherLayoutPolicy.activePillHeight / 3
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.launcherHeaderTopInset,
            ModeSwitcherLayoutPolicy.activePillHeight / 12
        )
        XCTAssertEqual(ModeSwitcherLayoutPolicy.launcherHeaderHorizontalInset, 0)
    }

    func testActiveTextPillProgressInsetExpandsOnlyWhenShowingProgress() {
        let baseInset = ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress: false)
        let progressInset = ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress: true)

        XCTAssertEqual(baseInset, ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset)
        XCTAssertGreaterThan(progressInset, baseInset)
        XCTAssertEqual(
            progressInset - baseInset,
            ModeSwitcherLayoutPolicy.activeTextPillProgressWidth + ModeSwitcherLayoutPolicy.activePillHeight / 4
        )
    }

    func testFilesPathMarqueeUsesFixedPathWidthInsidePill() {
        let pathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
            in: 420,
            path: "/Users/test/Very Long Folder Name/Deep/File.txt"
        )

        XCTAssertEqual(ModeSwitcherLayoutPolicy.filesPathMarqueeWidth(in: 420), pathWidth)
        XCTAssertLessThan(pathWidth, 420)
    }

    @MainActor
    func testWindowKeyStatePublishesOnlyOnValueChange() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore()
        )

        XCTAssertFalse(model.isWindowKey)
        model.setWindowKeyState(true)
        XCTAssertTrue(model.isWindowKey)
        model.setWindowKeyState(true)
        XCTAssertTrue(model.isWindowKey)
        model.setWindowKeyState(false)
        XCTAssertFalse(model.isWindowKey)
    }
}
