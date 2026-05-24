import XCTest
import Carbon
@testable import Bucky

final class LauncherModeRoutingTests: XCTestCase {
    func testLauncherModesAreOrderedForCommandShortcuts() {
        XCTAssertEqual(LauncherMode.ordered, [
            .applications,
            .calculator,
            .dictionary,
            .files,
            .agenda
        ])
    }

    func testCommandShortcutNumbersResolveModes() {
        XCTAssertEqual(LauncherMode(commandNumber: 1), .applications)
        XCTAssertEqual(LauncherMode(commandNumber: 2), .calculator)
        XCTAssertEqual(LauncherMode(commandNumber: 3), .dictionary)
        XCTAssertEqual(LauncherMode(commandNumber: 4), .files)
        XCTAssertEqual(LauncherMode(commandNumber: 5), .agenda)
        XCTAssertNil(LauncherMode(commandNumber: 6))
    }

    func testModeCycleWrapsThroughOrderedModes() {
        XCTAssertEqual(LauncherMode.applications.previousMode, .agenda)
        XCTAssertEqual(LauncherMode.applications.nextMode, .calculator)
        XCTAssertEqual(LauncherMode.calculator.nextMode, .dictionary)
        XCTAssertEqual(LauncherMode.dictionary.nextMode, .files)
        XCTAssertEqual(LauncherMode.files.nextMode, .agenda)
        XCTAssertEqual(LauncherMode.agenda.nextMode, .applications)
        XCTAssertEqual(LauncherMode.agenda.previousMode, .files)
    }

    func testModePlaceholdersAreSeparated() {
        XCTAssertEqual(LauncherMode.applications.placeholder, "Search Apps Here")
        XCTAssertEqual(LauncherMode.calculator.placeholder, "Perform Calculations Here")
        XCTAssertEqual(LauncherMode.dictionary.placeholder, "Search Dictionary Here")
        XCTAssertEqual(LauncherMode.files.placeholder, "Browse Files")
        XCTAssertEqual(LauncherMode.agenda.placeholder, "Agenda Scratchpad")
    }

    func testTextInputFocusModesExcludeFiles() {
        XCTAssertTrue(LauncherMode.applications.acceptsTextInput)
        XCTAssertTrue(LauncherMode.calculator.acceptsTextInput)
        XCTAssertTrue(LauncherMode.dictionary.acceptsTextInput)
        XCTAssertFalse(LauncherMode.files.acceptsTextInput)
        XCTAssertTrue(LauncherMode.agenda.acceptsTextInput)
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
        for key in ["1", "2", "3", "4", "5", "r", ",", "p", "[", "]"] {
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

    func testFilesModeRestoresFocusWhenAppReactivatesAfterPermissionPrompt() {
        XCTAssertTrue(LauncherWindowFocusRestorationPolicy.shouldRestoreAfterAppActivation(
            mode: .files,
            isPinned: false,
            isPresented: true,
            isVisible: true,
            isKeyWindow: false
        ))
        XCTAssertFalse(LauncherWindowFocusRestorationPolicy.shouldRestoreAfterAppActivation(
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

    func testCommandArrowRoutingCyclesModesWhenLauncherIsActive() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("if event.isCommandLeftArrow"))
        XCTAssertTrue(source.contains("return self.handleLauncherCommand(.previousMode) ? nil : event"))
        XCTAssertTrue(source.contains("if event.isCommandRightArrow"))
        XCTAssertTrue(source.contains("return self.handleLauncherCommand(.nextMode) ? nil : event"))
        XCTAssertTrue(source.contains("return handleLauncherCommand(.previousMode)"))
        XCTAssertTrue(source.contains("return handleLauncherCommand(.nextMode)"))
    }

    func testHotKeyDoesNotAddExtraMainQueueHopWhenAlreadyOnMainThread() throws {
        let source = try source(named: "Sources/Bucky/App/HotKeyController.swift")

        XCTAssertTrue(source.contains("controller.triggerHotKey()"))
        XCTAssertTrue(source.contains("guard Thread.isMainThread else"))
        XCTAssertTrue(source.contains("onHotKey()"))
        XCTAssertFalse(source.contains("DispatchQueue.main.async {\n                    controller.onHotKey()\n                }"))
    }

    @available(macOS 26.0, *)
    func testHotKeyShowUsesNonAnimatedMaterializationForImmediateInput() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("transaction.disablesAnimations = true"))
        XCTAssertTrue(source.contains("withTransaction(transaction) {\n                model.isPresented = true\n            }\n            finishShow(transitionID: visibilityTransitionID)"))
        XCTAssertFalse(source.contains("scheduleApplicationReindexIfNeeded"))
        XCTAssertTrue(source.contains("startApplicationIndexSourceStream()"))
        XCTAssertFalse(source.contains("withAnimation(presentationAnimation, completionCriteria: .removed) {\n                model.isPresented = true"))
        XCTAssertFalse(source.contains("if mode == .applications {\n            DispatchQueue.main.async"))
    }

    @available(macOS 26.0, *)
    func testHideFadesWholeWindowBeforeRemovingSwiftUIContent() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("NSAnimationContext.runAnimationGroup"))
        XCTAssertTrue(source.contains("window.animator().alphaValue = 0"))
        XCTAssertTrue(source.contains("transaction.disablesAnimations = true\n                withTransaction(transaction) {\n                    self.model.isPresented = false\n                }"))
        XCTAssertFalse(source.contains("withAnimation(presentationAnimation, completionCriteria: .removed) {\n            model.isPresented = false"))
    }

    @available(macOS 26.0, *)
    func testSettingsTransitionPreservesVisibleWindowFrameAndDisplay() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("if shouldMaterialize {\n            positionWindow(animated: false)\n        }"))
        XCTAssertTrue(source.contains("let screen = targetDisplayScreen()"))
        XCTAssertTrue(source.contains("private func targetDisplayScreen() -> NSScreen?"))
        XCTAssertTrue(source.contains("if window.isVisible, let screen = window.screen"))
        XCTAssertFalse(source.contains("guard let screen = primaryDisplayScreen() ?? NSScreen.main"))
    }

    @available(macOS 26.0, *)
    func testTextInputModesCaptureTypedCharactersDuringShowAnimation() throws {
        let controller = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")
        let utilities = try source(named: "Sources/Bucky/UI/Shared/Utilities.swift")

        XCTAssertTrue(controller.contains("self.visibilityState == .showing,\n                   self.model.mode.acceptsTextInput,\n                   let character = event.launcherTextInputCharacter"))
        XCTAssertTrue(controller.contains("self.model.insertTextInput(character)"))
        XCTAssertTrue(model.contains("func insertTextInput(_ character: Character)"))
        XCTAssertTrue(model.contains("query.append(character)\n        queryDidChange()"))
        XCTAssertTrue(utilities.contains("var launcherTextInputCharacter: Character?"))
        XCTAssertTrue(utilities.contains("flags.intersection([.command, .control, .option]).isEmpty"))
    }

    @available(macOS 26.0, *)
    func testAgendaKeyboardCommandsAreReservedAndRouted() throws {
        let command = try source(named: "Sources/Bucky/UI/Shared/LauncherCommand.swift")
        let controller = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let utilities = try source(named: "Sources/Bucky/UI/Shared/Utilities.swift")

        XCTAssertTrue(command.contains("case createAgendaItem"))
        XCTAssertTrue(command.contains("case removeAgendaSelection"))
        XCTAssertTrue(command.contains("case saveAgendaNote"))
        XCTAssertTrue(command.contains("case agendaMoveSelection(AgendaNavigationDirection)"))
        XCTAssertTrue(utilities.contains("var isCommandEqual: Bool"))
        XCTAssertTrue(utilities.contains("var isCommandMinus: Bool"))
        XCTAssertTrue(utilities.contains("var isCommandS: Bool"))
        XCTAssertTrue(utilities.contains("var optionArrowDirection: AgendaNavigationDirection?"))
        XCTAssertTrue(utilities.contains("\"=\", \"-\", \"s\""))
        XCTAssertTrue(controller.contains("event.isCommandEqual"))
        XCTAssertTrue(controller.contains(".createAgendaItem"))
        XCTAssertTrue(controller.contains("event.isCommandMinus"))
        XCTAssertTrue(controller.contains(".removeAgendaSelection"))
        XCTAssertTrue(controller.contains("event.isCommandS"))
        XCTAssertTrue(controller.contains(".saveAgendaNote"))
        XCTAssertTrue(controller.contains("event.optionArrowDirection"))
        XCTAssertTrue(controller.contains(".agendaMoveSelection(direction)"))
    }

    @available(macOS 26.0, *)
    func testModeSwitchDoesNotSynchronouslyReloadHistoryStores() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")

        XCTAssertFalse(source.contains("calculationHistoryStore.load()\n            dictionaryHistoryStore.load()"))
        XCTAssertTrue(source.contains("scheduleModeSnapshot(for: nextMode"))
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
                    fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
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
        XCTAssertFalse(try source(named: "Sources/Bucky/UI/SwiftUI/LauncherWindowFramePolicy.swift").contains("shadowBleed"))
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
                    fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
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
    func testModeCycleCommandsUseDoublyLinkedModeOrder() {
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
        _ = model.handle(command: .previousMode)
        XCTAssertEqual(model.mode, .agenda)

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
                fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
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
                fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
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
                fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )
    }

    private func source(named path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
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
                directoryStream: ImmediateDirectoryStream(fileSystem: client),
                fileServices: fileServices
            )
        )
    }
}
