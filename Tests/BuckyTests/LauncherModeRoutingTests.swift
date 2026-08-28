import AppKit
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

    func testModeCycleWrapsThroughOrderedModes() {
        XCTAssertEqual(LauncherMode.applications.previousMode, .files)
        XCTAssertEqual(LauncherMode.applications.nextMode, .calculator)
        XCTAssertEqual(LauncherMode.calculator.nextMode, .dictionary)
        XCTAssertEqual(LauncherMode.dictionary.nextMode, .files)
        XCTAssertEqual(LauncherMode.files.nextMode, .applications)
        XCTAssertEqual(LauncherMode.files.previousMode, .dictionary)
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

    func testLauncherModesBridgeToStoneCatalogEntries() {
        XCTAssertEqual(LauncherMode.applications.stoneID, .applications)
        XCTAssertEqual(LauncherMode.calculator.stoneID, .calculator)
        XCTAssertEqual(LauncherMode.dictionary.stoneID, .dictionary)
        XCTAssertEqual(LauncherMode.files.stoneID, .files)

        XCTAssertEqual(LauncherMode(stoneID: .applications), .applications)
        XCTAssertEqual(LauncherMode(stoneID: .calculator), .calculator)
        XCTAssertEqual(LauncherMode(stoneID: .dictionary), .dictionary)
        XCTAssertEqual(LauncherMode(stoneID: .files), .files)

        XCTAssertEqual(LauncherMode.applications.stoneDefinition, StoneCatalog.definition(for: .applications))
        XCTAssertEqual(LauncherMode.calculator.stoneDefinition, StoneCatalog.definition(for: .calculator))
        XCTAssertEqual(LauncherMode.dictionary.stoneDefinition, StoneCatalog.definition(for: .dictionary))
        XCTAssertEqual(LauncherMode.files.stoneDefinition, StoneCatalog.definition(for: .files))
    }

    @available(macOS 26.0, *)
    func testNearestSelectionScrollTracksImmediatelyForKeyRepeat() {
        XCTAssertFalse(SelectionScrollAnimationPolicy.shouldAnimate(anchor: .nearest))
        XCTAssertTrue(SelectionScrollAnimationPolicy.shouldAnimate(anchor: .top))
        XCTAssertTrue(SelectionScrollAnimationPolicy.shouldAnimate(anchor: .bottom))
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

    func testTextInputModesPassThroughNativeEditingCommands() {
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .calculator,
            fileFocusState: nil,
            charactersIgnoringModifiers: "v",
            modifierFlags: .command,
            eventType: .keyDown
        ))
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .dictionary,
            fileFocusState: nil,
            charactersIgnoringModifiers: "a",
            modifierFlags: .command,
            eventType: .keyDown
        ))
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .applications,
            fileFocusState: nil,
            charactersIgnoringModifiers: "c",
            modifierFlags: .command,
            eventType: .keyDown
        ))
    }

    func testTextInputModesPassThroughNativeEditingCommandsOnKeyUp() {
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .calculator,
            fileFocusState: nil,
            charactersIgnoringModifiers: "x",
            modifierFlags: .command,
            eventType: .keyUp
        ))
    }

    func testModifiedNativeEditingCommandsDoNotPassThrough() {
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .calculator,
            fileFocusState: nil,
            charactersIgnoringModifiers: "v",
            modifierFlags: [.command, .shift],
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .calculator,
            fileFocusState: nil,
            charactersIgnoringModifiers: "v",
            modifierFlags: [.command, .option],
            eventType: .keyDown
        ))
    }

    func testLauncherCommandsDoNotPassThroughAsTextEditingCommands() {
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .calculator,
            fileFocusState: nil,
            charactersIgnoringModifiers: "2",
            modifierFlags: .command,
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .applications,
            fileFocusState: nil,
            charactersIgnoringModifiers: "r",
            modifierFlags: .command,
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .applications,
            fileFocusState: nil,
            charactersIgnoringModifiers: "p",
            modifierFlags: .command,
            eventType: .keyDown
        ))
    }

    func testReservedLauncherCommandKeysDoNotPassThroughAsTextEditingCommands() {
        for key in ["1", "2", "3", "4", "r", ",", "p", "[", "]"] {
            XCTAssertFalse(
                LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
                    mode: .applications,
                    fileFocusState: nil,
                    charactersIgnoringModifiers: key,
                    modifierFlags: .command,
                    eventType: .keyDown
                ),
                "Expected Command+\(key) to remain reserved for launcher routing"
            )
        }
    }

    func testFilesRenamePassesThroughNativeEditingCommands() {
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .files,
            fileFocusState: .renaming,
            charactersIgnoringModifiers: "v",
            modifierFlags: .command,
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .files,
            fileFocusState: .browse,
            charactersIgnoringModifiers: "v",
            modifierFlags: .command,
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .files,
            fileFocusState: .previewActions,
            charactersIgnoringModifiers: "v",
            modifierFlags: .command,
            eventType: .keyDown
        ))
    }

    func testFilesModeDoesNotHideLauncherWhenPermissionPromptStealsFocus() {
        XCTAssertFalse(LauncherWindowDismissalPolicy.shouldHideOnResignKey(
            mode: .files,
            isPinned: false
        ))
        XCTAssertTrue(LauncherWindowDismissalPolicy.shouldHideOnResignKey(
            mode: .applications,
            isPinned: false
        ))
        XCTAssertFalse(LauncherWindowDismissalPolicy.shouldHideOnResignKey(
            mode: .applications,
            isPinned: true
        ))
    }

    func testPresentedVisibleLauncherRestoresFocusWhenAppReactivatesWithoutKeyWindow() {
        XCTAssertTrue(LauncherWindowFocusRestorationPolicy.shouldRestoreAfterAppActivation(
            mode: .files,
            isPinned: false,
            isPresented: true,
            isVisible: true,
            isKeyWindow: false
        ))
        XCTAssertTrue(LauncherWindowFocusRestorationPolicy.shouldRestoreAfterAppActivation(
            mode: .applications,
            isPinned: false,
            isPresented: true,
            isVisible: true,
            isKeyWindow: false
        ))
        XCTAssertFalse(LauncherWindowFocusRestorationPolicy.shouldRestoreAfterAppActivation(
            mode: .files,
            isPinned: false,
            isPresented: true,
            isVisible: true,
            isKeyWindow: true
        ))
    }

    func testLauncherFocusClaimRetriesAreBoundedAndStopAfterFocusIsOwned() {
        XCTAssertEqual(LauncherWindowFocusClaimPolicy.retryDelays, [0.016, 0.04, 0.08])
        XCTAssertTrue(LauncherWindowFocusClaimPolicy.shouldRetry(isWindowKey: false))
        XCTAssertFalse(LauncherWindowFocusClaimPolicy.shouldRetry(isWindowKey: true))
    }

    func testLauncherWindowUsesKeyCapablePanelBehavior() {
        let panel = BuckyPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testTypedCharacterIsCapturedWhileLauncherShowTransitionIsStillShowing() throws {
        let driver = HoldingAlphaAnimationDriver()
        let controller = LiquidGlassLauncherWindowController(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            dictionaryHistoryStore: DictionaryHistoryStore(),
            hotKeyChangeHandler: { _ in true },
            alphaDriverFactory: { _ in driver }
        )
        defer { controller.hide() }

        controller.show()
        pumpMainRunLoop()

        let model = try XCTUnwrap(launcherModel(for: controller))
        let phase = try XCTUnwrap(visibilityPhase(for: controller))
        XCTAssertEqual(phase, .showing)
        XCTAssertEqual(model.query, "")

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_A)
        ))

        NSApp.sendEvent(event)
        pumpMainRunLoop()

        XCTAssertEqual(model.query, "a")
        XCTAssertEqual(visibilityPhase(for: controller), .showing)
    }

    @available(macOS 26.0, *)
    func testQuickLookPreviewDoesNotResizeLauncherWindow() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = LauncherWindowFramePolicy.frame(
            mode: .files,
            fileFocusState: .quickLook(FileBrowserPreview(
                url: URL(fileURLWithPath: "/Users/test/photo.jpg"),
                mode: .nativeThumbnail
            )),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.size, LauncherWindowFramePolicy.defaultSize)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testQuickLookPreviewWindowUsesFullVisibleScreenHeight() {
        let visibleFrame = CGRect(x: 120, y: 48, width: 1_440, height: 900)
        let frame = FileBrowserPreviewWindowFramePolicy.frame(
            for: .nativeThumbnail,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.height, visibleFrame.height)
        XCTAssertEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.width, visibleFrame.width)
        XCTAssertEqual(frame.midX, visibleFrame.midX)
    }

    @available(macOS 26.0, *)
    func testLauncherWindowBackgroundCanDragFromMainPanel() {
        XCTAssertTrue(LauncherWindowDragPolicy.isMovableByWindowBackground)
        XCTAssertFalse(FileBrowserDragPolicy.mouseDownCanMoveWindow)
    }

    @available(macOS 26.0, *)
    func testQuickLookAndFileNavigationCommandsDoNotRepositionLauncherWindow() {
        XCTAssertFalse(LauncherWindowRepositionPolicy.shouldReposition(after: .beginSpaceHold))
        XCTAssertFalse(LauncherWindowRepositionPolicy.shouldReposition(after: .endSpaceHold))
        XCTAssertFalse(LauncherWindowRepositionPolicy.shouldReposition(after: .down))
        XCTAssertFalse(LauncherWindowRepositionPolicy.shouldReposition(after: .up))
        XCTAssertTrue(LauncherWindowRepositionPolicy.shouldReposition(after: .switchMode(.files)))
        XCTAssertTrue(LauncherWindowRepositionPolicy.shouldReposition(after: .previousMode))
        XCTAssertTrue(LauncherWindowRepositionPolicy.shouldReposition(after: .nextMode))
    }

    @available(macOS 26.0, *)
    func testWindowOpenCloseAnimationUsesConfiguredPresentationPolicy() {
        XCTAssertEqual(LauncherWindowPresentationAnimationPolicy.duration(for: .smooth), 0.20)
        XCTAssertEqual(LauncherWindowPresentationAnimationPolicy.duration(for: .snappy), 0.10)
        XCTAssertEqual(
            timingFunctionControlPoints(LauncherWindowPresentationAnimationPolicy.timingFunction(for: .smooth)),
            [[0, 0], [0.42, 0], [0.58, 1], [1, 1]]
        )
        XCTAssertEqual(
            timingFunctionControlPoints(LauncherWindowPresentationAnimationPolicy.timingFunction(for: .snappy)),
            [[0, 0], [0, 0], [0.58, 1], [1, 1]]
        )
    }

    @MainActor
    @available(macOS 26.0, *)
    func testSwitchingToApplicationsDoesNotSynchronouslyRequestReindex() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore()
        )
        var reindexCount = 0
        model.reindexAction = { reindexCount += 1 }

        model.show(mode: .calculator)
        _ = model.handle(command: .switchMode(.applications))

        XCTAssertEqual(model.mode, .applications)
        XCTAssertEqual(reindexCount, 0)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testModeSwitchPublishesModeBeforeDeferredSnapshotWork() {
        var activationCount = 0
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModelFactory: {
                activationCount += 1
                return FileBrowserModel(
                    fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                    store: InMemoryFileBrowserStore(state: .defaultValue),
                    directoryStream: ImmediateDirectoryStream()
                )
            }
        )

        model.show(mode: .applications)
        XCTAssertEqual(activationCount, 0)

        _ = model.handle(command: .switchMode(.files))

        XCTAssertEqual(model.mode, .files)
        XCTAssertEqual(activationCount, 0)
    }

    @available(macOS 26.0, *)
    func testDefaultWindowFrameUsesRealPanelBoundsNotShadowBleed() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = LauncherWindowFramePolicy.frame(
            mode: .applications,
            fileFocusState: nil,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(LauncherWindowFramePolicy.visualContentSize, CGSize(width: 760, height: 460))
        XCTAssertEqual(frame.size, LauncherWindowFramePolicy.visualContentSize)
        XCTAssertEqual(LauncherWindowFramePolicy.defaultSize, LauncherWindowFramePolicy.visualContentSize)
    }

    @available(macOS 26.0, *)
    func testSettingsModeKeepsLauncherWindowSize() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let launcherSize = LauncherWindowFramePolicy.windowSize(
            mode: .applications,
            fileFocusState: nil,
            visibleFrame: visibleFrame
        )
        let settingsSize = LauncherWindowFramePolicy.windowSize(
            mode: .applications,
            fileFocusState: nil,
            isShowingSettings: true,
            visibleFrame: visibleFrame
        )
        let settingsFrame = LauncherWindowFramePolicy.frame(
            mode: .applications,
            fileFocusState: nil,
            isShowingSettings: true,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(settingsSize, launcherSize)
        XCTAssertEqual(settingsFrame.size, launcherSize)
    }

    @available(macOS 26.0, *)
    func testInactiveWindowVisualPolicyDimsWholeSurfaceWithoutSuppressingIcons() {
        XCTAssertEqual(LauncherWindowFocusVisualPolicy.contentOpacity(isKeyWindow: true), 1)
        XCTAssertEqual(LauncherWindowFocusVisualPolicy.dimOverlayOpacity(isKeyWindow: true), 0)
        XCTAssertEqual(LauncherWindowFocusVisualPolicy.blurRadius(isKeyWindow: true), 0)

        XCTAssertLessThan(
            LauncherWindowFocusVisualPolicy.contentOpacity(isKeyWindow: false),
            LauncherWindowFocusVisualPolicy.contentOpacity(isKeyWindow: true)
        )
        XCTAssertGreaterThan(LauncherWindowFocusVisualPolicy.dimOverlayOpacity(isKeyWindow: false), 0)
        XCTAssertGreaterThan(LauncherWindowFocusVisualPolicy.blurRadius(isKeyWindow: false), 0)
        XCTAssertEqual(
            LauncherWindowFocusVisualPolicy.iconOpacity(isKeyWindow: false),
            LauncherWindowFocusVisualPolicy.textOpacity(isKeyWindow: false)
        )
        XCTAssertGreaterThan(LauncherWindowFocusVisualPolicy.iconOpacity(isKeyWindow: false), 0)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testBackgroundWarmerActivatesFileBrowserCacheBeforeFilesModeIsShown() {
        var activationCount = 0
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModelFactory: {
                activationCount += 1
                return FileBrowserModel(
                    fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                    store: InMemoryFileBrowserStore(state: .defaultValue),
                    directoryStream: ImmediateDirectoryStream()
                )
            }
        )

        XCTAssertEqual(activationCount, 0)
        model.startBackgroundWarmCaches()
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(activationCount, 1)

        model.show(mode: .applications)
        XCTAssertEqual(activationCount, 1)
        _ = model.handle(command: .switchMode(.calculator))
        XCTAssertEqual(activationCount, 1)

        _ = model.handle(command: .switchMode(.dictionary))
        XCTAssertEqual(activationCount, 1)

        _ = model.handle(command: .switchMode(.applications))
        XCTAssertEqual(activationCount, 1)

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
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
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
    func testResetPanelVisibilityAfterHideClearsBothPanelFlags() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore()
        )

        model.isShowingSettings = true
        model.isShowingHelp = true

        XCTAssertTrue(model.isShowingSettings)
        XCTAssertTrue(model.isShowingHelp)

        model.resetPanelVisibilityAfterHide()

        XCTAssertFalse(model.isShowingSettings)
        XCTAssertFalse(model.isShowingHelp)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testModeCycleCommandsUseDoublyLinkedModeOrder() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )

        model.show(mode: .applications)
        _ = model.handle(command: .previousMode)
        XCTAssertEqual(model.mode, .files)

        _ = model.handle(command: .nextMode)
        XCTAssertEqual(model.mode, .applications)

        _ = model.handle(command: .nextMode)
        XCTAssertEqual(model.mode, .calculator)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testBlankDictionaryModeDoesNotUseCalculatorHistoryMessage() {
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        )

        model.show(mode: .dictionary)

        XCTAssertEqual(model.toolItems, [])
        XCTAssertNil(model.emptyMessage)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testBlankDictionaryModeShowsPersistedHistoryRows() {
        let dictionaryHistoryStore = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        dictionaryHistoryStore.add(term: "apple")
        dictionaryHistoryStore.add(term: "banana")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: dictionaryHistoryStore)

        model.show(mode: .dictionary)

        XCTAssertEqual(model.toolItems.map(\.kind), [.dictionaryHistory, .dictionaryHistory])
        XCTAssertEqual(model.toolItems.map(\.title), ["banana", "apple"])
        XCTAssertTrue(model.toolItems.allSatisfy { $0.copyText == nil })
        XCTAssertNil(model.emptyMessage)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionaryHistoryRowCanBeRemovedIndividually() {
        let dictionaryHistoryStore = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        dictionaryHistoryStore.add(term: "apple")
        dictionaryHistoryStore.add(term: "banana")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: dictionaryHistoryStore)

        model.show(mode: .dictionary)
        guard let banana = model.toolItems.first(where: { $0.title == "banana" }) else {
            return XCTFail("Expected banana dictionary history row")
        }

        model.removeDictionaryHistory(banana)

        XCTAssertEqual(model.toolItems.map(\.title), ["apple"])
        XCTAssertEqual(dictionaryHistoryStore.words.map(\.term), ["apple"])
        XCTAssertNil(model.emptyMessage)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionaryHistoryActivationMovesTermToTop() {
        let dictionaryHistoryStore = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        dictionaryHistoryStore.add(term: "apple")
        dictionaryHistoryStore.add(term: "banana")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: dictionaryHistoryStore)

        model.show(mode: .dictionary)
        model.isPinned = true
        model.selectedIndex = 1
        model.selectionScrollRequest = nil
        _ = model.handle(command: .open)

        XCTAssertEqual(dictionaryHistoryStore.words.map(\.term), ["apple", "banana"])
        XCTAssertEqual(model.toolItems.first?.title, "apple")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectionScrollRequest?.index, 0)
        XCTAssertEqual(model.selectionScrollRequest?.anchor, .top)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionaryLookupIsDeferredAndPublishesOnlyLatestSnapshot() {
        let lookup = RecordingDictionaryLookup()
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL()),
            dictionaryLookup: { query in lookup.results(for: query) }
        )

        model.show(mode: .dictionary)
        model.query = "app"
        model.queryDidChange()

        XCTAssertEqual(lookup.queries, [])
        XCTAssertEqual(model.toolItems, [])

        model.query = "apple"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))

        XCTAssertEqual(lookup.queries, ["apple"])
        XCTAssertEqual(model.toolItems.map(\.title), ["apple"])
        XCTAssertEqual(model.toolItems.map(\.subtitle), ["Definition for apple"])
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCalculatorLiveResultSelectsAndScrollsToTopRowWhileTyping() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )

        model.show(mode: .calculator)
        model.query = "1 + 1"
        model.queryDidChange()
        model.selectedIndex = 1

        model.query = "2 + 2 ="
        model.queryDidChange()

        XCTAssertEqual(model.toolItems.first?.kind, .calculation)
        XCTAssertEqual(model.toolItems.first?.title, "4")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectionScrollRequest?.index, 0)
        XCTAssertEqual(model.selectionScrollRequest?.anchor, .top)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCalculatorHistoryCommitDoesNotStealHistorySelection() {
        let calculationHistoryStore = CalculationHistoryStore()
        calculationHistoryStore.clear()
        defer { calculationHistoryStore.clear() }
        calculationHistoryStore.add(expression: "3 + 3", result: "6")
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: calculationHistoryStore,
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )

        model.show(mode: .calculator)
        model.query = "2 + 2"
        model.queryDidChange()
        model.selectedIndex = 1
        model.selectionScrollRequest = nil

        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        XCTAssertEqual(model.toolItems.first?.kind, .calculation)
        XCTAssertEqual(model.toolItems.first?.title, "4")
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertNil(model.selectionScrollRequest)
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
    func testFilesFocusedOpenActionHidesLauncherAfterSuccessfulOpen() {
        let service = RecordingFileBrowserServices()
        let model = makeFileLauncherModel(entries: ["alpha.txt"], fileServices: service)
        var didHide = false
        model.hideAction = { didHide = true }

        model.show(mode: .files)
        _ = model.handle(command: .open)
        XCTAssertEqual(model.fileBrowserModel.focusState, .previewActions)

        _ = model.handle(command: .open)

        XCTAssertTrue(didHide)
        XCTAssertEqual(service.events, [
            .open(URL(fileURLWithPath: "/Users/test/alpha.txt"))
        ])
        XCTAssertEqual(model.fileBrowserModel.focusState, .browse)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCommandPInFilesPinsSelectedPathInsteadOfWindow() {
        let model = makeFileLauncherModel(entries: ["alpha.txt", "beta.txt"])

        model.show(mode: .files)
        _ = model.handle(command: .down)
        _ = model.handle(command: .togglePin)

        XCTAssertFalse(model.isPinned)
        XCTAssertEqual(model.fileBrowserModel.pinnedDirectories.map(\.lastPathComponent), ["beta.txt"])
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
    private func makeDictionaryLauncherModel(
        dictionaryHistoryStore: DictionaryHistoryStore,
        dictionaryLookup: @escaping @Sendable (String) -> [DictionaryResult] = { DictionaryLookup.results(for: $0) }
    ) -> LiquidGlassLauncherModel {
        LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            dictionaryHistoryStore: dictionaryHistoryStore,
            dictionaryLookup: dictionaryLookup,
            dictionaryOpenHandler: { _ in },
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )
    }

    private func timingFunctionControlPoints(_ timingFunction: CAMediaTimingFunction) -> [[Float]] {
        (0..<4).map { index in
            var point = [Float](repeating: 0, count: 2)
            timingFunction.getControlPoint(at: index, values: &point)
            return point
        }
    }

    private final class RecordingDictionaryLookup: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedQueries: [String] = []

        var queries: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedQueries
        }

        func results(for query: String) -> [DictionaryResult] {
            lock.lock()
            recordedQueries.append(query)
            lock.unlock()

            return [
                DictionaryResult(
                    term: query,
                    definition: "Definition for \(query)"
                )
            ]
        }
    }

    private func temporaryDictionaryHistoryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyDictionaryHistory-\(UUID().uuidString).json")
    }

    @MainActor
    @available(macOS 26.0, *)
    private func makeFileLauncherModel(
        entries names: [String],
        fileServices: FileBrowserNativeServicing = RecordingFileBrowserServices()
    ) -> LiquidGlassLauncherModel {
        let home = TestFixtures.userHome
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
                directoryStream: ImmediateDirectoryStream(fileSystem: client),
                fileServices: fileServices
            )
        )
    }

    @available(macOS 26.0, *)
    private final class HoldingAlphaAnimationDriver: LauncherWindowAlphaAnimationDriver {
        var alphaValue: CGFloat = 0

        func cancelAndNormalize() {}

        @discardableResult
        func animate(
            to alpha: CGFloat,
            duration: TimeInterval,
            timingFunction: CAMediaTimingFunction,
            completion: @escaping @MainActor () -> Void
        ) -> Bool {
            alphaValue = alpha
            return true
        }
    }

    @available(macOS 26.0, *)
    private func launcherModel(for controller: LiquidGlassLauncherWindowController) -> LiquidGlassLauncherModel? {
        mirroredChild(named: "model", in: controller) as? LiquidGlassLauncherModel
    }

    @available(macOS 26.0, *)
    @MainActor
    private func visibilityPhase(for controller: LiquidGlassLauncherWindowController) -> WindowVisibilityState? {
        let coordinator = mirroredChild(named: "visibilityTransitionCoordinator", in: controller)
            as? LauncherWindowVisibilityTransitionCoordinator
        return coordinator?.phase
    }

    private func mirroredChild(named name: String, in value: Any) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }

    private func pumpMainRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}
