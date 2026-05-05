import XCTest
import Carbon
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

    func testTextInputFocusModesExcludeFiles() {
        XCTAssertTrue(LauncherMode.applications.acceptsTextInput)
        XCTAssertTrue(LauncherMode.calculator.acceptsTextInput)
        XCTAssertTrue(LauncherMode.dictionary.acceptsTextInput)
        XCTAssertFalse(LauncherMode.files.acceptsTextInput)
    }

    func testFilesRenameFocusDoesNotRouteAlphaNumericKeysAwayFromTextField() {
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldRouteAlphaNumeric(
            mode: .files,
            fileFocusState: .browse
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldRouteAlphaNumeric(
            mode: .files,
            fileFocusState: .renaming
        ))
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldRouteAlphaNumeric(
            mode: .applications,
            fileFocusState: nil
        ))
    }

    func testFilesRenameFocusPassesTextEditingKeysExceptReturnAndEscape() {
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughFileTextEditing(
            mode: .files,
            fileFocusState: .renaming,
            keyCode: UInt16(kVK_Space),
            eventType: .keyDown
        ))
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughFileTextEditing(
            mode: .files,
            fileFocusState: .renaming,
            keyCode: UInt16(kVK_LeftArrow),
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughFileTextEditing(
            mode: .files,
            fileFocusState: .renaming,
            keyCode: UInt16(kVK_Return),
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughFileTextEditing(
            mode: .files,
            fileFocusState: .renaming,
            keyCode: UInt16(kVK_Escape),
            eventType: .keyDown
        ))
    }

    @MainActor
    @available(macOS 26.0, *)
    func testFileBrowserModelActivatesOnlyWhenFilesModeIsShown() {
        var activationCount = 0
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModelFactory: {
                activationCount += 1
                return FileBrowserModel(
                    fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
                    store: InMemoryFileBrowserStore(state: .defaultValue),
                    directoryStream: ImmediateDirectoryStream()
                )
            }
        )

        model.show(mode: .applications)
        XCTAssertEqual(activationCount, 0)

        _ = model.handle(command: .switchMode(.calculator))
        XCTAssertEqual(activationCount, 0)

        _ = model.handle(command: .switchMode(.dictionary))
        XCTAssertEqual(activationCount, 0)

        _ = model.handle(command: .switchMode(.applications))
        XCTAssertEqual(activationCount, 0)

        _ = model.handle(command: .switchMode(.files))
        XCTAssertEqual(activationCount, 1)

        _ = model.handle(command: .switchMode(.applications))
        _ = model.handle(command: .switchMode(.files))
        XCTAssertEqual(activationCount, 1)
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
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
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
        _ = model.handle(command: .switchMode(.calculator))
        XCTAssertEqual(model.query, "2+2")
        _ = model.handle(command: .switchMode(.dictionary))
        XCTAssertEqual(model.query, "hello")
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
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )

        model.show(mode: .dictionary)

        XCTAssertNil(model.emptyMessage)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testFilesTopBottomKeepLauncherAndFileSelectionAligned() {
        let model = makeFileLauncherModel(entries: ["alpha.txt", "beta.txt", "gamma.txt"])

        model.show(mode: .files)
        _ = model.handle(command: .down)
        _ = model.handle(command: .down)
        XCTAssertEqual(model.selectedIndex, 2)
        XCTAssertEqual(model.fileBrowserModel.selectedEntry?.name, "gamma.txt")

        _ = model.handle(command: .top)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.fileBrowserModel.selectedEntry?.name, "alpha.txt")

        _ = model.handle(command: .bottom)
        XCTAssertEqual(model.selectedIndex, 2)
        XCTAssertEqual(model.fileBrowserModel.selectedEntry?.name, "gamma.txt")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testFilesEscapeClosesPreviewActionsBeforeHidingLauncher() {
        let model = makeFileLauncherModel(entries: ["alpha.txt"])
        var didHide = false
        model.hideAction = { didHide = true }

        model.show(mode: .files)
        _ = model.handle(command: .open)
        XCTAssertEqual(model.fileBrowserModel.focusState, .previewActions)

        _ = model.handle(command: .close)

        XCTAssertEqual(model.fileBrowserModel.focusState, .browse)
        XCTAssertFalse(didHide)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testFilesEscapeStepsPendingTransferBackToActionsBeforeHidingLauncher() {
        let model = makeFileLauncherModel(entries: ["alpha.txt"])
        var didHide = false
        model.hideAction = { didHide = true }

        model.show(mode: .files)
        _ = model.handle(command: .space)
        model.fileBrowserModel.startTransfer(.copy)
        XCTAssertEqual(model.fileBrowserModel.focusState, .transferPending(.copy(model.fileBrowserModel.selectedURLs)))

        _ = model.handle(command: .close)

        XCTAssertEqual(model.fileBrowserModel.focusState, .previewActions)
        XCTAssertFalse(didHide)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDirectModeSwitchCanCancelActiveFileSpaceHold() {
        let model = makeFileLauncherModel(entries: ["alpha.txt"])
        model.modeWillSwitchAction = { oldMode, nextMode in
            if oldMode == .files, nextMode != .files {
                _ = model.handle(command: .endSpaceHold)
            }
        }

        model.show(mode: .files)
        _ = model.handle(command: .beginSpaceHold)
        XCTAssertEqual(model.fileBrowserModel.focusState, .quickLook(FileBrowserPreview(
            url: model.fileBrowserModel.selectedEntry!.url,
            mode: .metadataFallback
        )))

        _ = model.handle(command: .switchMode(.calculator))

        XCTAssertEqual(model.fileBrowserModel.focusState, .browse)
    }

    @MainActor
    @available(macOS 26.0, *)
    private func makeFileLauncherModel(entries names: [String]) -> LiquidGlassLauncherModel {
        let home = URL(fileURLWithPath: "/Users/test")
        let entries = names.map { name in
            FileBrowserEntry(
                url: home.appendingPathComponent(name),
                kind: .file,
                size: 1,
                createdAt: nil,
                modifiedAt: nil,
                isHidden: false
            )
        }
        let client = StubFileSystemClient(home: home, entriesByDirectory: [home: entries])
        return LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModel: FileBrowserModel(
                fileSystem: client,
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream(fileSystem: client)
            )
        )
    }
}
