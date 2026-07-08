import Carbon
import XCTest
@testable import Bucky

private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Bool) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

final class LauncherModeRoutingTests: XCTestCase {
    func testAppsDictionaryPreviewUsesApplicationDictionaryRoute() throws {
        let controller = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")
        let view = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(controller.contains("model.isApplicationDictionaryActive"))
        XCTAssertTrue(controller.contains("model.mode == .files || model.isApplicationDictionaryActive"))
        XCTAssertTrue(model.contains("dictionaryRouteIsActive"))
        XCTAssertTrue(model.contains("pendingDictionaryPreviewTask"))
        XCTAssertTrue(view.contains("model.isApplicationDictionaryActive"))
        XCTAssertTrue(view.contains("LauncherModeTintPolicy.panelColor(for: .dictionary(term:"))
    }
    func testLauncherModesAreOrderedForCommandShortcuts() {
        XCTAssertEqual(LauncherMode.ordered, [
            .applications,
            .files
        ])
    }

    func testCommandShortcutNumbersResolveModes() {
        XCTAssertEqual(LauncherMode(commandNumber: 1), .applications)
        XCTAssertNil(LauncherMode(commandNumber: 2))
        XCTAssertNil(LauncherMode(commandNumber: 3))
        XCTAssertEqual(LauncherMode(commandNumber: 4), .files)
        XCTAssertNil(LauncherMode(commandNumber: 5))
        XCTAssertNil(LauncherMode(commandNumber: 6))
    }

    func testModeCycleWrapsThroughOrderedModes() {
        XCTAssertEqual(LauncherMode.applications.previousMode, .files)
        XCTAssertEqual(LauncherMode.applications.nextMode, .files)
        XCTAssertEqual(LauncherMode.files.nextMode, .applications)
    }

    func testModePlaceholdersAreSeparated() {
        XCTAssertEqual(LauncherMode.applications.placeholder, "Search Apps Here")
        XCTAssertEqual(LauncherMode.files.placeholder, "Browse Files")
    }

    func testTextInputFocusModesExcludeFiles() {
        XCTAssertTrue(LauncherMode.applications.acceptsTextInput)
        XCTAssertFalse(LauncherMode.files.acceptsTextInput)
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
            mode: .applications,
            fileFocusState: nil,
            charactersIgnoringModifiers: "v",
            modifierFlags: .command,
            eventType: .keyDown
        ))
        XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .applications,
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
            mode: .applications,
            fileFocusState: nil,
            charactersIgnoringModifiers: "x",
            modifierFlags: .command,
            eventType: .keyUp
        ))
    }

    func testModifiedNativeEditingCommandsDoNotPassThrough() {
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .applications,
            fileFocusState: nil,
            charactersIgnoringModifiers: "v",
            modifierFlags: [.command, .shift],
            eventType: .keyDown
        ))
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .applications,
            fileFocusState: nil,
            charactersIgnoringModifiers: "v",
            modifierFlags: [.command, .option],
            eventType: .keyDown
        ))
    }

    func testLauncherCommandsDoNotPassThroughAsTextEditingCommands() {
        XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
            mode: .applications,
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

    func testLauncherFocusClaimsKeyWindowWithoutForegroundActivation() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("private func activateAndFocusWindow()"))
        XCTAssertTrue(source.contains("window.orderFrontRegardless()\n        window.makeKeyAndOrderFront(nil)"))
        XCTAssertFalse(source.contains("NSRunningApplication.current.activate"))
        XCTAssertFalse(source.contains("NSApp.activate()"))
        XCTAssertFalse(source.contains("NSApp.activate(ignoringOtherApps: true)"))
    }

    func testLauncherFocusClaimRetriesAreBoundedAndStopAfterFocusIsOwned() {
        XCTAssertEqual(LauncherWindowFocusClaimPolicy.retryDelays, [0.016, 0.04, 0.08])
        XCTAssertTrue(LauncherWindowFocusClaimPolicy.shouldRetry(isWindowKey: false))
        XCTAssertFalse(LauncherWindowFocusClaimPolicy.shouldRetry(isWindowKey: true))
    }

    func testLauncherWindowUsesKeyCapableNonactivatingPanel() throws {
        let panelSource = try source(named: "Sources/Bucky/UI/Shared/BuckyPanelWindow.swift")
        let controllerSource = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(panelSource.contains("final class BuckyPanelWindow: NSPanel"))
        XCTAssertTrue(panelSource.contains("override var canBecomeKey: Bool { true }"))
        XCTAssertTrue(controllerSource.contains("styleMask: [.borderless, .resizable, .nonactivatingPanel]"))
        XCTAssertTrue(controllerSource.contains("window.becomesKeyOnlyIfNeeded = false"))
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

    func testDictionaryModeUsesHoldSpacePreviewRouter() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("if event.keyCode == UInt16(kVK_Space), self.usesSpaceHoldPreview"))
        XCTAssertTrue(source.contains("return self.handleSpacePreviewEvent(event)"))
        XCTAssertTrue(source.contains("private var usesSpaceHoldPreview: Bool"))
        XCTAssertTrue(source.contains("model.mode == .files || model.isApplicationDictionaryActive"))
    }

    func testDictionaryPreviewOverlayUsesModeTintAndRetainsStateForCloseAnimation() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(source.contains("@State private var renderedDictionaryPreview: DictionaryDefinitionPreview?"))
        XCTAssertTrue(source.contains("@State private var isDictionaryPreviewVisible = false"))
        XCTAssertTrue(source.contains("DictionaryDefinitionPreviewOverlay(preview: dictionaryPreview, tint: LauncherModeTintPolicy.panelColor(for: .dictionary(term:"))
        XCTAssertTrue(source.contains(".opacity(isDictionaryPreviewVisible ? 1 : 0)"))
        XCTAssertTrue(source.contains(".scaleEffect(isDictionaryPreviewVisible ? 1 : 0.985)"))
        XCTAssertTrue(source.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertTrue(source.contains("let tint: Color"))
        XCTAssertTrue(source.contains(".foregroundStyle(tint)"))
        XCTAssertTrue(source.contains(".glassEffect(.regular.tint(tint.opacity("))
        XCTAssertFalse(source.contains(".glassEffect(.regular.tint(Color.mint"))
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
        XCTAssertTrue(source.contains("withTransaction(transaction) {\n                model.isPresented = true\n            }\n            animateWindowOpen(transitionID: visibilityTransitionID)"))
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
    func testHotKeyShowFadesWholeWindowAfterNonAnimatedContentMaterialization() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("window.alphaValue = shouldMaterialize ? 0 : 1"))
        XCTAssertTrue(source.contains("withTransaction(transaction) {\n                model.isPresented = true\n            }\n            animateWindowOpen(transitionID: visibilityTransitionID)"))
        XCTAssertTrue(source.contains("windowOpenAnimationScheduler.schedule("))
        XCTAssertTrue(source.contains("startAnimation: { [weak self] completion in"))
        XCTAssertTrue(source.contains("window.animator().alphaValue = 1"))
        XCTAssertTrue(source.contains("completion()"))
        XCTAssertTrue(source.contains("completionAction: { [weak self] in"))
        XCTAssertTrue(source.contains("self?.finishShow(transitionID: transitionID)"))
    }

    @available(macOS 26.0, *)
    func testWindowOpenCloseAnimationUsesConfiguredPresentationPolicy() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")

        XCTAssertTrue(source.contains("private enum LauncherWindowPresentationAnimationPolicy"))
        XCTAssertTrue(source.contains("static func duration(for timing: LauncherAnimationTiming) -> TimeInterval"))
        XCTAssertTrue(source.contains("case .smooth:\n            return 0.20"))
        XCTAssertTrue(source.contains("case .snappy:\n            return 0.10"))
        XCTAssertTrue(source.contains("static func timingFunction(for timing: LauncherAnimationTiming) -> CAMediaTimingFunction"))
        XCTAssertTrue(source.contains("case .smooth:\n            return CAMediaTimingFunction(name: .easeInEaseOut)"))
        XCTAssertTrue(source.contains("case .snappy:\n            return CAMediaTimingFunction(name: .easeOut)"))
        XCTAssertTrue(source.contains("context.duration = LauncherWindowPresentationAnimationPolicy.duration(for: model.animationTiming)"))
        XCTAssertTrue(source.contains("context.timingFunction = LauncherWindowPresentationAnimationPolicy.timingFunction(for: model.animationTiming)"))
        XCTAssertFalse(source.contains("static let duration: TimeInterval = 0.12"))
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

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
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

        _ = model.handle(command: .switchMode(.applications))
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
        XCTAssertEqual(model.mode, .files)

        _ = model.handle(command: .nextMode)
        XCTAssertEqual(model.mode, .applications)

        _ = model.handle(command: .nextMode)
        XCTAssertEqual(model.mode, .files)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testBlankDictionaryModeDoesNotUseCalculatorHistoryMessage() {
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        )

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()

        XCTAssertEqual(model.toolItems, [])
        XCTAssertEqual(model.emptyMessage, "No dictionary matches")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testBlankDictionaryModeShowsPersistedHistoryRows() {
        let dictionaryHistoryStore = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        dictionaryHistoryStore.add(term: "apple")
        dictionaryHistoryStore.add(term: "banana")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: dictionaryHistoryStore)

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()

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

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
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

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
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

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        model.query = "?app"
        model.queryDidChange()

        XCTAssertEqual(lookup.queries, [])
        XCTAssertEqual(model.toolItems, [])

        model.query = "?apple"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))

        XCTAssertEqual(lookup.queries, ["apple"])
        XCTAssertEqual(model.toolItems.map(\.title), ["apple"])
        XCTAssertEqual(model.toolItems.map(\.subtitle), ["Definition for apple"])
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionarySpaceHoldShowsAndClearsFullDefinitionPreview() {
        let fullDefinition = """
        apple | noun
        The round fruit of a tree of the rose family.

        Example: She sliced an apple for breakfast.
        """
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL()),
            dictionaryLookup: { query in
                [
                    DictionaryResult(
                        term: query,
                        definition: fullDefinition
                    )
                ]
            }
        )

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        model.query = "?apple"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))

        XCTAssertNil(model.dictionaryPreview)
        XCTAssertTrue(model.handle(command: .beginSpaceHold))
        XCTAssertEqual(model.dictionaryPreview?.term, "apple")
        XCTAssertEqual(model.dictionaryPreview?.definition, fullDefinition)
        XCTAssertEqual(
            model.dictionaryPreview?.imageSearchURL?.absoluteString,
            "https://commons.wikimedia.org/w/index.php?search=file:apple&title=Special:MediaSearch&type=image"
        )

        XCTAssertTrue(model.handle(command: .endSpaceHold))
        XCTAssertNil(model.dictionaryPreview)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionaryHistorySpaceHoldLazilyLooksUpAndShowsDefinitionPreview() {
        let dictionaryHistoryStore = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        dictionaryHistoryStore.add(term: "apple")
        let lookup = RecordingDictionaryLookup()
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: dictionaryHistoryStore,
            dictionaryLookup: { query in lookup.results(for: query) }
        )

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        XCTAssertEqual(model.toolItems.first?.kind, .dictionaryHistory)
        XCTAssertNil(model.toolItems.first?.previewText)

        XCTAssertTrue(model.handle(command: .beginSpaceHold))
        XCTAssertEqual(model.dictionaryPreviewLoadingTerm, "apple")

        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(lookup.queries, ["apple"])
        XCTAssertEqual(
            model.dictionaryPreview,
            DictionaryDefinitionPreview(term: "apple", definition: "Definition for apple")
        )
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsDictionaryHistoryHoldIsConsumedAndStalePreviewIsInvalidatedByQueryChange() {
        let history = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        history.add(term: "apple")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history, dictionaryLookup: { query in
            Thread.sleep(forTimeInterval: 0.12)
            return [DictionaryResult(term: query, definition: "stale")]
        })

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        XCTAssertTrue(model.handle(command: .beginSpaceHold))
        XCTAssertEqual(model.dictionaryPreviewLoadingTerm, "apple")
        model.query = "?banana"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        XCTAssertNil(model.dictionaryPreview)
        XCTAssertNil(model.dictionaryPreviewLoadingTerm)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionaryHistoryPreviewRefreshOnArrowUsesCancelableLookupForNewSelection() {
        let history = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        history.add(term: "apple")
        history.add(term: "banana")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history, dictionaryLookup: { query in
            Thread.sleep(forTimeInterval: 0.08)
            return [DictionaryResult(term: query, definition: "Definition for \(query)")]
        })

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        XCTAssertTrue(model.handle(command: .beginSpaceHold))
        XCTAssertEqual(model.dictionaryPreviewLoadingTerm, "banana")
        XCTAssertTrue(model.handle(command: .down))
        XCTAssertEqual(model.dictionaryPreviewLoadingTerm, "apple")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(model.dictionaryPreview?.term, "apple")
        XCTAssertEqual(model.dictionaryPreview?.definition, "Definition for apple")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionaryHistoryArrowRefreshDoesNotInvokeLookupInline() {
        let history = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        history.add(term: "apple")
        history.add(term: "banana")
        let lookupStartedOffMain = LockedBool()
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history, dictionaryLookup: { query in
            lookupStartedOffMain.set(!Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.05)
            return [DictionaryResult(term: query, definition: "Definition for \(query)")]
        })

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        XCTAssertTrue(model.handle(command: .beginSpaceHold))
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        lookupStartedOffMain.set(false)
        XCTAssertTrue(model.handle(command: .down))
        XCTAssertFalse(lookupStartedOffMain.value)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(lookupStartedOffMain.value)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testHidingDuringDictionaryHistoryPreviewLookupInvalidatesLateResult() {
        let history = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        history.add(term: "apple")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history, dictionaryLookup: { query in
            Thread.sleep(forTimeInterval: 0.12)
            return [DictionaryResult(term: query, definition: "late result")]
        })

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        XCTAssertTrue(model.handle(command: .beginSpaceHold))
        XCTAssertEqual(model.dictionaryPreviewLoadingTerm, "apple")
        model.cancelDictionaryPreview()
        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertNil(model.dictionaryPreview)
        XCTAssertNil(model.dictionaryPreviewLoadingTerm)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionarySpaceHoldRefreshesPreviewWhenSelectionMovesThroughHistory() {
        let dictionaryHistoryStore = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        dictionaryHistoryStore.add(term: "apple")
        dictionaryHistoryStore.add(term: "banana")
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: dictionaryHistoryStore,
            dictionaryLookup: { query in
                [
                    DictionaryResult(
                        term: query,
                        definition: "Definition for \(query)"
                    )
                ]
            }
        )

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()

        XCTAssertEqual(model.toolItems.map(\.title), ["banana", "apple"])
        XCTAssertTrue(model.handle(command: .beginSpaceHold))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(model.dictionaryPreview?.term, "banana")

        XCTAssertTrue(model.handle(command: .down))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.dictionaryPreview?.term, "apple")
        XCTAssertEqual(model.dictionaryPreview?.definition, "Definition for apple")

        XCTAssertTrue(model.handle(command: .up))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.dictionaryPreview?.term, "banana")
        XCTAssertEqual(model.dictionaryPreview?.definition, "Definition for banana")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDictionarySpaceTapRemainsTextInputWhenHoldRouterIsActive() {
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        )

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()
        model.query = "?ice"
        model.queryDidChange()

        XCTAssertTrue(model.handle(command: .space))
        XCTAssertEqual(model.query, "?ice ")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsEqualsQueryShowsCalculatorResultAndSelectsTopRowWhileTyping() {
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
        model.query = "=1 + 1"
        model.queryDidChange()
        model.selectedIndex = 1

        model.query = "=2 + 2 ="
        model.queryDidChange()

        XCTAssertEqual(model.mode, .applications)
        XCTAssertTrue(model.isApplicationCalculatorActive)
        XCTAssertEqual(model.toolItems.first?.kind, .calculation)
        XCTAssertEqual(model.toolItems.first?.title, "4")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectionScrollRequest?.index, 0)
        XCTAssertEqual(model.selectionScrollRequest?.anchor, .top)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsQuestionQueryShowsDictionaryHistory() {
        let history = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        history.add(term: "apple")
        history.add(term: "banana")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history)

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()

        XCTAssertTrue(model.isApplicationDictionaryActive)
        XCTAssertEqual(model.toolItems.map(\.kind), [.dictionaryHistory, .dictionaryHistory])
        XCTAssertEqual(model.toolItems.map(\.title), ["banana", "apple"])
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsDictionaryRouteUsesToolResultCountAndNavigation() {
        let history = DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL())
        history.add(term: "apple")
        history.add(term: "banana")
        let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history)

        model.show(mode: .applications)
        model.query = "?"
        model.queryDidChange()

        XCTAssertTrue(model.isApplicationToolActive)
        XCTAssertEqual(model.resultCount, 2)
        XCTAssertEqual(model.selectedIndex, 0)

        XCTAssertTrue(model.handle(command: .down))
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.toolItems[model.selectedIndex].title, "apple")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsQuestionQueryPublishesLatestDictionaryLookupAfterDelay() {
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL()),
            dictionaryLookup: { query in
                [DictionaryResult(term: query, definition: "Definition for \(query)")]
            }
        )

        model.show(mode: .applications)
        model.query = "? apple"
        model.queryDidChange()

        XCTAssertTrue(model.isDictionaryLookupLoading)
        XCTAssertEqual(model.toolItems, [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))

        XCTAssertFalse(model.isDictionaryLookupLoading)
        XCTAssertEqual(model.toolItems.map(\.kind), [.dictionary])
        XCTAssertEqual(model.toolItems.map(\.title), ["apple"])
    }

    @MainActor
    @available(macOS 26.0, *)
    func testLeavingAppsQuestionLookupCancelsLoadingAndRestoresApplicationFiltering() {
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL()),
            dictionaryLookup: { _ in
                [DictionaryResult(term: "stale", definition: "Stale")]
            }
        )
        var reindexCount = 0
        model.reindexAction = { reindexCount += 1 }

        model.show(mode: .applications)
        model.query = "? apple"
        model.queryDidChange()
        XCTAssertTrue(model.isDictionaryLookupLoading)

        model.query = "Safari"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))

        XCTAssertFalse(model.isApplicationDictionaryActive)
        XCTAssertFalse(model.isDictionaryLookupLoading)
        XCTAssertTrue(model.toolItems.isEmpty)
        XCTAssertEqual(reindexCount, 0)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCancelledAppsQuestionLookupCannotPublishAfterRouteChanges() {
        let model = makeDictionaryLauncherModel(
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL()),
            dictionaryLookup: { query in
                Thread.sleep(forTimeInterval: 0.08)
                return [DictionaryResult(term: query, definition: "Late \(query)")]
            }
        )

        model.show(mode: .applications)
        model.query = "? apple"
        model.queryDidChange()
        model.query = "? banana"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.24))

        XCTAssertFalse(model.isDictionaryLookupLoading)
        XCTAssertEqual(model.toolItems.map(\.title), ["banana"])
        XCTAssertFalse(model.toolItems.contains { $0.title == "apple" })
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsEqualsQueryHistoryCommitDoesNotStealHistorySelection() {
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

        model.show(mode: .applications)
        model.query = "=2 + 2"
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
    func testAppsEqualsQueryHistoryActivationRestoresOriginalExpressionForEditing() {
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
        var didHide = false
        model.hideAction = { didHide = true }

        model.show(mode: .applications)
        model.query = "="
        model.queryDidChange()
        XCTAssertEqual(model.toolItems.first?.kind, .calculationHistory)
        XCTAssertEqual(model.toolItems.first?.inputText, "3 + 3")

        XCTAssertTrue(model.handle(command: .open))

        XCTAssertEqual(model.query, "=3 + 3")
        XCTAssertFalse(didHide)
        XCTAssertEqual(model.toolItems.first?.kind, .calculation)
        XCTAssertEqual(model.toolItems.first?.title, "6")
        XCTAssertEqual(model.selectedIndex, 0)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsEqualsQueryLiveResultActivationCopiesAndStaysOpenWithResultFeedback() {
        let calculationHistoryStore = CalculationHistoryStore()
        calculationHistoryStore.clear()
        defer { calculationHistoryStore.clear() }
        var copiedValues: [String] = []
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: calculationHistoryStore,
            pasteboardCopyHandler: { copiedValues.append($0) },
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )
        var didHide = false
        model.hideAction = { didHide = true }

        model.show(mode: .applications)
        model.query = "=109109100 + 1"
        model.queryDidChange()

        XCTAssertEqual(model.toolItems.first?.kind, .calculation)
        XCTAssertEqual(model.toolItems.first?.title, "109,109,101")

        XCTAssertTrue(model.handle(command: .open))

        XCTAssertEqual(copiedValues, ["109,109,101"])
        XCTAssertFalse(didHide)
        XCTAssertEqual(model.calculatorResultFeedback?.result, "109,109,101")
        XCTAssertEqual(calculationHistoryStore.calculations.first?.expression, "109109100 + 1")
        XCTAssertEqual(calculationHistoryStore.calculations.first?.result, "109,109,101")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsEqualsQueryCalculatorResultFeedbackClearsWhenQueryChanges() {
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            pasteboardCopyHandler: { _ in },
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )

        model.show(mode: .applications)
        model.query = "=2 + 2"
        model.queryDidChange()
        _ = model.handle(command: .open)
        XCTAssertEqual(model.calculatorResultFeedback?.result, "4")

        model.query = "=2 + 3"
        model.queryDidChange()

        XCTAssertNil(model.calculatorResultFeedback)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testAppsEqualsQueryCanStartAfterLeadingFiller() {
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
        model.query = "   =1,200 / 3"
        model.queryDidChange()

        XCTAssertTrue(model.isApplicationCalculatorActive)
        XCTAssertEqual(model.toolItems.first?.kind, .calculation)
        XCTAssertEqual(model.toolItems.first?.title, "400")
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

        _ = model.handle(command: .switchMode(.applications))

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
