import XCTest
@testable import Bucky

final class LauncherModeRoutingTests: XCTestCase {
    func testLauncherModesAreOrderedForCommandShortcuts() {
        XCTAssertEqual(LauncherMode.ordered, [
            .applications,
            .calculator,
            .dictionary,
            .files
        ])
    }

    func testCommandShortcutNumbersResolveModes() {
        XCTAssertEqual(LauncherMode(commandNumber: 1), .applications)
        XCTAssertEqual(LauncherMode(commandNumber: 2), .calculator)
        XCTAssertEqual(LauncherMode(commandNumber: 3), .dictionary)
        XCTAssertEqual(LauncherMode(commandNumber: 4), .files)
        XCTAssertNil(LauncherMode(commandNumber: 5))
    }

    func testModePlaceholdersAreSeparated() {
        XCTAssertEqual(LauncherMode.applications.placeholder, "Search Apps Here")
        XCTAssertEqual(LauncherMode.calculator.placeholder, "Perform Calculations Here")
        XCTAssertEqual(LauncherMode.dictionary.placeholder, "Search Dictionary Here")
        XCTAssertEqual(LauncherMode.files.placeholder, "Browse Files")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testSwitchingModesStoresIndependentQueries() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue)
            )
        )

        model.show(mode: .applications)
        model.query = "ray"
        _ = model.handle(command: .switchMode(.calculator))
        model.query = "2+2"
        _ = model.handle(command: .switchMode(.dictionary))
        model.query = "hello"
        _ = model.handle(command: .switchMode(.applications))

        XCTAssertEqual(model.query, "ray")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testBlankDictionaryModeDoesNotUseCalculatorHistoryMessage() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue)
            )
        )

        model.show(mode: .dictionary)

        XCTAssertNil(model.emptyMessage)
    }
}
