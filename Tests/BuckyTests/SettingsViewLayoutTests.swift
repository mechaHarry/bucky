import XCTest
@testable import Bucky

@MainActor
final class SettingsViewLayoutTests: XCTestCase {
    func testShowSettingsClearsHelpAndPinState() {
        let model = makeModel()
        model.isShowingHelp = true
        model.isPinned = true

        model.showSettings()

        XCTAssertTrue(model.isShowingSettings)
        XCTAssertFalse(model.isShowingHelp)
        XCTAssertFalse(model.isPinned)
    }

    func testShowHelpClearsSettingsAndPinState() {
        let model = makeModel()
        model.isShowingSettings = true
        model.isPinned = true

        model.showHelp()

        XCTAssertFalse(model.isShowingSettings)
        XCTAssertTrue(model.isShowingHelp)
        XCTAssertFalse(model.isPinned)
    }

    func testHideSettingsOnlyClearsSettingsFlag() {
        let model = makeModel()
        model.isShowingSettings = true
        model.isShowingHelp = true

        model.hideSettings()

        XCTAssertFalse(model.isShowingSettings)
        XCTAssertTrue(model.isShowingHelp)
    }

    func testHideHelpOnlyClearsHelpFlag() {
        let model = makeModel()
        model.isShowingSettings = true
        model.isShowingHelp = true

        model.hideHelp()

        XCTAssertTrue(model.isShowingSettings)
        XCTAssertFalse(model.isShowingHelp)
    }

    func testShowLauncherSurfaceClearsPanelFlagsWithoutChangingMode() {
        let model = makeModel()
        model.mode = .dictionary
        model.isShowingSettings = true
        model.isShowingHelp = true

        model.showLauncherSurface()

        XCTAssertEqual(model.mode, .dictionary)
        XCTAssertFalse(model.isShowingSettings)
        XCTAssertFalse(model.isShowingHelp)
    }

    private func makeModel() -> LiquidGlassLauncherModel {
        LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore()
        )
    }
}
