import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
@MainActor
final class LiquidGlassLauncherWindowController: NSObject, LauncherControlling {
    private let window: BuckyPanelWindow
    private let model: LiquidGlassLauncherModel
    private var settingsModel: SettingsViewModel!
    private var localKeyMonitor: Any?
    private var settingsHotKeyEventMonitor: Any?
    private var applicationActivationObserver: NSObjectProtocol?
    private var quickLookPreviewPanel: NSPanel?
    private var quickLookPreviewHost: NSHostingController<QuickLookPreviewSurface>?
    private var spaceKeyRouter = LauncherSpaceKeyRouter()
    private var pendingSpaceHoldTimer: Timer?
    private var isOptionPinnedFocusActive = false
    private var visibilityState: WindowVisibilityState = .hidden
    private var visibilityTransitionID = 0
    private var applicationIndexSourceStream: ApplicationIndexSourceStream?
    private var presentationAnimationDuration: TimeInterval {
        0.24
    }

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        dictionaryHistoryStore: DictionaryHistoryStore,
        hotKeyChangeHandler: @escaping @MainActor (HotKeyConfiguration) -> Bool
    ) {
        model = LiquidGlassLauncherModel(
            settingsStore: settingsStore,
            inclusionStore: inclusionStore,
            exclusionStore: exclusionStore,
            calculationHistoryStore: calculationHistoryStore,
            dictionaryHistoryStore: dictionaryHistoryStore
        )
        window = BuckyPanelWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: LauncherWindowFramePolicy.defaultSize.width,
                height: LauncherWindowFramePolicy.defaultSize.height
            ),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        settingsModel = SettingsViewModel(
            settingsStore: settingsStore,
            inclusionStore: inclusionStore,
            exclusionStore: exclusionStore,
            hotKeyChangeHandler: hotKeyChangeHandler,
            inclusionsChangedHandler: { [weak self] in
                self?.refreshAfterInclusionsChanged()
            },
            exclusionsChangedHandler: { [weak self] in
                self?.refreshAfterExclusionsChanged()
            },
            settingsChangedHandler: { [weak self] in
                self?.refreshAfterSettingsChanged()
            }
        )
        settingsModel.startHotKeyRecordingAction = { [weak self] in
            self?.startRecordingSettingsHotKey()
        }
        settingsModel.presentIncludedAppPickerAction = { [weak self] in
            self?.presentIncludedAppPicker()
        }
        settingsModel.presentFileBrowserStartDirectoryPickerAction = { [weak self] in
            self?.presentFileBrowserStartDirectoryPicker()
        }

        model.hideAction = { [weak self] in self?.hide() }
        model.openSettingsAction = { [weak self] in self?.toggleSettings() }
        model.openHelpAction = { [weak self] in self?.toggleHelp() }
        model.returnToLauncherAction = { [weak self] in self?.showLauncherFromPanel() }
        model.reindexAction = { [weak self] in self?.reindex() }
        model.pinnedChangedAction = { [weak self] isPinned in
            self?.setPinned(isPinned)
        }
        model.modeWillSwitchAction = { [weak self] oldMode, nextMode in
            if oldMode == .files, nextMode != .files {
                self?.cancelSpaceHoldState(deliverEndHold: true)
                self?.cancelOptionPinnedFocus()
            }
        }
        buildWindow()
        installLocalKeyMonitor()
        installApplicationActivationObserver()
        startApplicationIndexSourceStream()
        reindex()
        model.startBackgroundWarmCaches()
    }

    deinit {
        MainActor.assumeIsolated {
            cancelSpaceHoldState(deliverEndHold: true)
            cancelOptionPinnedFocus()
            closeQuickLookPreviewPanel()
            applicationIndexSourceStream?.stop()
            stopRecordingSettingsHotKey()
            if let localKeyMonitor {
                NSEvent.removeMonitor(localKeyMonitor)
            }
            if let applicationActivationObserver {
                NotificationCenter.default.removeObserver(applicationActivationObserver)
            }
        }
    }

    func toggle() {
        if model.isShowingSettings || model.isShowingHelp {
            showLauncherFromPanel()
            return
        }

        if model.isPinned {
            focusPinnedWindow()
            return
        }

        switch visibilityState {
        case .hidden, .hiding:
            show()
        case .showing, .shown:
            hide()
        }
    }

    func show() {
        show(mode: .applications)
    }

    func showSettings() {
        beginVisibilityTransition(.showing)
        closeQuickLookPreviewPanel()
        cancelSpaceHoldState(deliverEndHold: true)
        cancelOptionPinnedFocus()
        settingsModel.refresh()

        let shouldMaterialize = !window.isVisible || !model.isPresented
        if shouldMaterialize {
            model.isPresented = false
        }
        model.showSettings()
        if shouldMaterialize {
            positionWindow(animated: false)
        }
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.setWindowKeyState(true)
        if shouldMaterialize {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.isPresented = true
            }
        }
        finishShow(transitionID: visibilityTransitionID)
    }

    private func showHelp() {
        beginVisibilityTransition(.showing)
        closeQuickLookPreviewPanel()
        cancelSpaceHoldState(deliverEndHold: true)
        cancelOptionPinnedFocus()
        settingsModel.refresh()

        let shouldMaterialize = !window.isVisible || !model.isPresented
        if shouldMaterialize {
            model.isPresented = false
        }
        model.showHelp()
        if shouldMaterialize {
            positionWindow(animated: false)
        }
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.setWindowKeyState(true)
        if shouldMaterialize {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.isPresented = true
            }
        }
        finishShow(transitionID: visibilityTransitionID)
    }

    private func toggleSettings() {
        if model.isShowingSettings {
            showLauncherFromPanel()
        } else {
            showSettings()
        }
    }

    private func toggleHelp() {
        if model.isShowingHelp {
            showLauncherFromPanel()
        } else {
            showHelp()
        }
    }

    private func showLauncherFromPanel() {
        stopRecordingSettingsHotKey()
        model.showLauncherSurface()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.setWindowKeyState(true)
    }

    private func show(mode: LauncherMode) {
        stopRecordingSettingsHotKey()
        beginVisibilityTransition(.showing)
        let shouldMaterialize = !window.isVisible || !model.isPresented
        model.show(mode: mode)
        if shouldMaterialize {
            model.isPresented = false
        }
        positionWindow(animated: false)
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.setWindowKeyState(true)
        if shouldMaterialize {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.isPresented = true
            }
            finishShow(transitionID: visibilityTransitionID)
        } else {
            finishShow(transitionID: visibilityTransitionID)
        }
    }

    func hide() {
        guard visibilityState != .hidden,
              visibilityState != .hiding else {
            return
        }

        beginVisibilityTransition(.hiding)
        closeQuickLookPreviewPanel()
        cancelSpaceHoldState(deliverEndHold: true)
        cancelOptionPinnedFocus()
        stopRecordingSettingsHotKey()
        model.cancelPendingCalculationHistory()

        let transitionID = visibilityTransitionID
        NSAnimationContext.runAnimationGroup { [weak self] context in
            guard let self else { return }
            context.duration = presentationAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.visibilityTransitionID == transitionID,
                      self.visibilityState == .hiding else {
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.model.isPresented = false
                }
                self.finishHide(transitionID: transitionID)
            }
        }
    }

    func reindex() {
        model.reindex()
    }

    func refreshAfterExclusionsChanged() {
        model.refreshAfterExclusionsChanged()
    }

    func refreshAfterInclusionsChanged() {
        model.reindex()
    }

    func refreshAfterSettingsChanged() {
        model.refreshAfterSettingsChanged()
    }

    private func startRecordingSettingsHotKey() {
        stopRecordingSettingsHotKey(resetModel: false)

        settingsHotKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecordingSettingsHotKey()
                return nil
            }

            guard let hotKey = HotKeyConfiguration(event: event) else {
                NSSound.beep()
                return nil
            }

            self.settingsModel.commitHotKey(hotKey)
            self.stopRecordingSettingsHotKey(resetModel: false)
            return nil
        }
    }

    private func stopRecordingSettingsHotKey(resetModel: Bool = true) {
        if let settingsHotKeyEventMonitor {
            NSEvent.removeMonitor(settingsHotKeyEventMonitor)
            self.settingsHotKeyEventMonitor = nil
        }

        if resetModel {
            settingsModel.cancelHotKeyRecording()
        }
    }

    private func presentIncludedAppPicker() {
        let panel = NSOpenPanel()
        panel.title = "Add Included App"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.applicationBundle]

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.settingsModel.addIncludedApps(panel.urls)
        }
    }

    private func presentFileBrowserStartDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Files Start Folder"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.urls.first else { return }
            self?.settingsModel.setFileBrowserStartDirectory(url)
        }
    }

    private func buildWindow() {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = LauncherWindowDragPolicy.isMovableByWindowBackground
        window.minSize = LauncherWindowFramePolicy.minimumSize
        window.delegate = self
        window.keyEquivalentHandler = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
        }
        window.cancelHandler = { [weak self] in
            self?.handleLauncherCommand(.close) ?? false
        }

        let hostingView = BuckyPanelHostingView(rootView: LiquidGlassLauncherView(
            model: model,
            settingsModel: settingsModel
        ))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = LauncherVisualStyle.windowCornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self,
                  self.window.isVisible,
                  self.window.isKeyWindow || self.window.isMainWindow else {
                return event
            }

            if event.type == .flagsChanged, self.model.mode == .files {
                return self.handleFileModifierEvent(event)
            }

            if self.model.isShowingSettings {
                guard event.type == .keyDown else { return event }
                if event.isCommandComma {
                    return self.handleLauncherCommand(.settings) ? nil : event
                }
                if event.isCommandSlash {
                    return self.handleLauncherCommand(.help) ? nil : event
                }
                if event.keyCode == UInt16(kVK_Escape) {
                    return self.handleLauncherCommand(.close) ? nil : event
                }
                return event
            }

            if self.model.isShowingHelp {
                guard event.type == .keyDown else { return event }
                if event.isCommandSlash {
                    return self.handleLauncherCommand(.help) ? nil : event
                }
                if event.isCommandComma {
                    return self.handleLauncherCommand(.settings) ? nil : event
                }
                if event.keyCode == UInt16(kVK_Escape) {
                    return self.handleLauncherCommand(.close) ? nil : event
                }
                return event
            }

            if LauncherKeyRoutingPolicy.shouldPassThroughFileTextEditing(
                mode: self.model.mode,
                fileFocusState: self.model.mode == .files ? self.fileBrowserFocusState : nil,
                keyCode: event.keyCode,
                eventType: event.type
            ), !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
                return event
            }

            if LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
                mode: self.model.mode,
                fileFocusState: self.model.mode == .files ? self.fileBrowserFocusState : nil,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags,
                eventType: event.type
            ) {
                return event
            }

            if event.keyCode == UInt16(kVK_Space), self.model.mode == .files {
                return self.handleFileSpaceEvent(event)
            }

            guard event.type == .keyDown else {
                return event
            }

            if let mode = event.commandNumberMode {
                return self.handleLauncherCommand(.switchMode(mode)) ? nil : event
            }
            if event.isCommandR {
                return self.handleLauncherCommand(.reindex) ? nil : event
            }
            if event.isCommandComma {
                return self.handleLauncherCommand(.settings) ? nil : event
            }
            if event.isCommandSlash {
                return self.handleLauncherCommand(.help) ? nil : event
            }
            if event.isCommandP {
                return self.handleLauncherCommand(.togglePin) ? nil : event
            }
            if event.isCommandLeftBracket {
                return self.handleLauncherCommand(.historyBack) ? nil : event
            }
            if event.isCommandRightBracket {
                return self.handleLauncherCommand(.historyForward) ? nil : event
            }
            if event.isCommandUpArrow {
                return self.handleLauncherCommand(.top) ? nil : event
            }
            if event.isCommandDownArrow {
                return self.handleLauncherCommand(.bottom) ? nil : event
            }
            if event.isCommandLeftArrow {
                return self.handleLauncherCommand(.previousMode) ? nil : event
            }
            if event.isCommandRightArrow {
                return self.handleLauncherCommand(.nextMode) ? nil : event
            }

            switch event.keyCode {
            case UInt16(kVK_UpArrow):
                return self.handleLauncherCommand(.up) ? nil : event
            case UInt16(kVK_DownArrow):
                return self.handleLauncherCommand(.down) ? nil : event
            case UInt16(kVK_LeftArrow):
                return self.handleLauncherCommand(.left) ? nil : event
            case UInt16(kVK_RightArrow):
                return self.handleLauncherCommand(.right) ? nil : event
            case UInt16(kVK_Space):
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                    return self.handleLauncherCommand(.shiftSpace) ? nil : event
                }
                return self.handleLauncherCommand(.space) ? nil : event
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                return self.handleLauncherCommand(.open) ? nil : event
            case UInt16(kVK_Escape):
                return self.handleLauncherCommand(.close) ? nil : event
            default:
                if self.visibilityState == .showing,
                   self.model.mode.acceptsTextInput,
                   let character = event.launcherTextInputCharacter {
                    self.model.insertTextInput(character)
                    return nil
                }
                if self.model.mode == .files,
                   let routedCharacter = event.fileNavigationAlphaNumericCharacter,
                   LauncherKeyRoutingPolicy.shouldRouteAlphaNumeric(
                       mode: self.model.mode,
                       fileFocusState: self.fileBrowserFocusState
                   ) {
                    let command: LauncherCommand = routedCharacter.isReverse
                        ? .shiftAlphaNumeric(routedCharacter.character)
                        : .alphaNumeric(routedCharacter.character)
                    return self.handleLauncherCommand(command) ? nil : event
                } else if let character = event.firstAlphaNumericCharacter,
                          LauncherKeyRoutingPolicy.shouldRouteAlphaNumeric(
                              mode: self.model.mode,
                              fileFocusState: self.model.mode == .files ? self.fileBrowserFocusState : nil
                          ) {
                    return self.handleLauncherCommand(.alphaNumeric(character)) ? nil : event
                }
                return event
            }
        }
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        if let mode = event.commandNumberMode {
            return handleLauncherCommand(.switchMode(mode))
        }
        if event.isCommandR {
            return handleLauncherCommand(.reindex)
        }
        if event.isCommandComma {
            return handleLauncherCommand(.settings)
        }
        if event.isCommandSlash {
            return handleLauncherCommand(.help)
        }
        if event.isCommandP {
            return handleLauncherCommand(.togglePin)
        }
        if event.isCommandLeftBracket {
            return handleLauncherCommand(.historyBack)
        }
        if event.isCommandRightBracket {
            return handleLauncherCommand(.historyForward)
        }
        if event.isCommandUpArrow {
            return handleLauncherCommand(.top)
        }
        if event.isCommandDownArrow {
            return handleLauncherCommand(.bottom)
        }
        if event.isCommandLeftArrow {
            return handleLauncherCommand(.previousMode)
        }
        if event.isCommandRightArrow {
            return handleLauncherCommand(.nextMode)
        }
        return false
    }

    private func installApplicationActivationObserver() {
        guard applicationActivationObserver == nil else { return }

        applicationActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.restoreFocusAfterExternalPromptIfNeeded()
            }
        }
    }

    private func startApplicationIndexSourceStream() {
        let stream = ApplicationIndexSourceStream { [weak self] in
            self?.reindex()
        }
        applicationIndexSourceStream = stream
        stream.start()
    }

    private func handleLauncherCommand(_ command: LauncherCommand) -> Bool {
        if model.isShowingSettings {
            switch command {
            case .settings:
                toggleSettings()
                return true
            case .help:
                showHelp()
                return true
            case .close:
                hide()
                return true
            default:
                return false
            }
        }

        if model.isShowingHelp {
            switch command {
            case .help:
                toggleHelp()
                return true
            case .settings:
                showSettings()
                return true
            case .close:
                hide()
                return true
            default:
                return false
            }
        }

        let handled = model.handle(command: command)
        if handled {
            syncQuickLookPreviewPanel()
        }
        if handled, LauncherWindowRepositionPolicy.shouldReposition(after: command) {
            positionWindow(animated: true)
        }
        return handled
    }

    private var fileBrowserFocusState: FileBrowserFocusState {
        MainActor.assumeIsolated {
            model.fileBrowserModel.focusState
        }
    }

    private func handleFileSpaceEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isShift = flags == .shift
            guard flags.isEmpty || isShift else {
                return event
            }
            return performSpaceKeyDecision(
                spaceKeyRouter.keyDown(isShift: isShift, isRepeat: event.isARepeat),
                event: event
            )
        case .keyUp:
            return performSpaceKeyDecision(spaceKeyRouter.keyUp(), event: event)
        default:
            return event
        }
    }

    private func performSpaceKeyDecision(
        _ decision: LauncherSpaceKeyDecision,
        event: NSEvent?
    ) -> NSEvent? {
        switch decision {
        case .pass:
            return event
        case .consume:
            return nil
        case .scheduleHold:
            _ = handleLauncherCommand(.prepareSpaceInteraction)
            scheduleSpaceHold()
            return nil
        case .sendSpace:
            cancelPendingSpaceHold()
            return handleLauncherCommand(.space) ? nil : event
        case .sendShiftSpace:
            cancelPendingSpaceHold()
            return handleLauncherCommand(.shiftSpace) ? nil : event
        case .sendBeginHold:
            return handleLauncherCommand(.beginSpaceHold) ? nil : event
        case .sendEndHold:
            cancelPendingSpaceHold()
            return handleLauncherCommand(.endSpaceHold) ? nil : event
        }
    }

    private func scheduleSpaceHold() {
        pendingSpaceHoldTimer?.invalidate()
        pendingSpaceHoldTimer = Timer.scheduledTimer(
            withTimeInterval: LauncherSpaceKeyRouter.holdDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingSpaceHoldTimer = nil
                _ = self.performSpaceKeyDecision(
                    self.spaceKeyRouter.holdDelayElapsed(),
                    event: nil
                )
            }
        }
    }

    private func cancelPendingSpaceHold() {
        pendingSpaceHoldTimer?.invalidate()
        pendingSpaceHoldTimer = nil
    }

    private func cancelSpaceHoldState(deliverEndHold: Bool) {
        cancelPendingSpaceHold()
        let decision = spaceKeyRouter.cancel()
        guard deliverEndHold, decision == .sendEndHold else { return }
        _ = model.handle(command: .endSpaceHold)
    }

    private func handleFileModifierEvent(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isOptionDown = flags.contains(.option)

        if isOptionDown, !isOptionPinnedFocusActive {
            isOptionPinnedFocusActive = true
            return handleLauncherCommand(.beginPinnedFocus) ? nil : event
        }

        if !isOptionDown, isOptionPinnedFocusActive {
            isOptionPinnedFocusActive = false
            return handleLauncherCommand(.endPinnedFocus) ? nil : event
        }

        return event
    }

    private func cancelOptionPinnedFocus() {
        guard isOptionPinnedFocusActive else { return }
        isOptionPinnedFocusActive = false
        _ = model.handle(command: .endPinnedFocus)
    }

    private func positionWindow(animated: Bool) {
        guard let screen = targetDisplayScreen() else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = LauncherWindowFramePolicy.frame(
            mode: model.mode,
            fileFocusState: model.mode == .files ? fileBrowserFocusState : nil,
            isShowingSettings: model.isShowingSettings,
            visibleFrame: visibleFrame
        )

        guard window.frame != frame else { return }
        window.setFrame(frame, display: true, animate: animated)
    }

    private func targetDisplayScreen() -> NSScreen? {
        if window.isVisible, let screen = window.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? primaryDisplayScreen() ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func syncQuickLookPreviewPanel() {
        guard !model.isShowingSettings,
              model.mode == .files,
              case let .quickLook(preview) = fileBrowserFocusState else {
            closeQuickLookPreviewPanel()
            return
        }

        let previewPayload = MainActor.assumeIsolated {
            let fileBrowserModel = model.fileBrowserModel
            return (
                model: fileBrowserModel,
                entry: fileBrowserModel.entry(for: preview.url)
            )
        }
        let rootView = QuickLookPreviewSurface(
            model: previewPayload.model,
            preview: preview,
            entry: previewPayload.entry
        )

        if let quickLookPreviewHost {
            quickLookPreviewHost.rootView = rootView
        } else {
            let host = NSHostingController(rootView: rootView)
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = host
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
            panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
            quickLookPreviewHost = host
            quickLookPreviewPanel = panel
        }

        positionQuickLookPreviewPanel(for: preview.mode)
        quickLookPreviewPanel?.orderFront(nil)
    }

    private func positionQuickLookPreviewPanel(for mode: FileBrowserPreviewMode) {
        guard let quickLookPreviewPanel,
              let screen = window.screen ?? primaryDisplayScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let frame = FileBrowserPreviewWindowFramePolicy.frame(
            for: mode,
            visibleFrame: screen.visibleFrame
        )
        guard quickLookPreviewPanel.frame != frame else { return }
        quickLookPreviewPanel.setFrame(frame, display: true, animate: false)
    }

    private func closeQuickLookPreviewPanel() {
        quickLookPreviewPanel?.orderOut(nil)
        quickLookPreviewPanel = nil
        quickLookPreviewHost = nil
    }

    private func restoreFocusAfterExternalPromptIfNeeded() {
        guard LauncherWindowFocusRestorationPolicy.shouldRestoreAfterAppActivation(
            mode: model.mode,
            isPinned: model.isPinned,
            isPresented: model.isPresented,
            isVisible: window.isVisible,
            isKeyWindow: window.isKeyWindow
        ) else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        model.setWindowKeyState(true)
    }

    private func setPinned(_ isPinned: Bool) {
        window.level = isPinned ? .statusBar : .floating
    }

    private func focusPinnedWindow() {
        guard window.isVisible else {
            show()
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.setWindowKeyState(true)
    }

    private func beginVisibilityTransition(_ state: WindowVisibilityState) {
        visibilityTransitionID += 1
        visibilityState = state
    }

    private func finishShow(transitionID: Int) {
        guard visibilityTransitionID == transitionID,
              visibilityState == .showing else {
            return
        }

        visibilityState = .shown
    }

    private func finishHide(transitionID: Int) {
        guard visibilityTransitionID == transitionID,
              visibilityState == .hiding else {
            return
        }

        window.makeFirstResponder(nil)
        window.orderOut(nil)
        window.resignKey()
        model.hideSettings()
        visibilityState = .hidden
    }

}

@available(macOS 26.0, *)
private enum WindowVisibilityState {
    case hidden
    case showing
    case shown
    case hiding
}

enum LauncherSpaceKeyDecision: Equatable {
    case pass
    case consume
    case scheduleHold
    case sendSpace
    case sendShiftSpace
    case sendBeginHold
    case sendEndHold
}

struct LauncherSpaceKeyRouter {
    static let holdDelay: TimeInterval = 0.28

    private var isPendingHold = false
    private var isHolding = false

    mutating func keyDown(isShift: Bool, isRepeat: Bool) -> LauncherSpaceKeyDecision {
        if isShift {
            isPendingHold = false
            isHolding = false
            return isRepeat ? .consume : .sendShiftSpace
        }

        if isRepeat {
            guard !isPendingHold, !isHolding else {
                return .consume
            }

            isPendingHold = true
            return .scheduleHold
        }

        guard !isPendingHold, !isHolding else {
            return .consume
        }

        isPendingHold = true
        return .scheduleHold
    }

    mutating func keyUp() -> LauncherSpaceKeyDecision {
        if isHolding {
            isHolding = false
            return .sendEndHold
        }

        if isPendingHold {
            isPendingHold = false
            return .sendSpace
        }

        return .pass
    }

    mutating func holdDelayElapsed() -> LauncherSpaceKeyDecision {
        guard isPendingHold else {
            return .pass
        }

        isPendingHold = false
        isHolding = true
        return .sendBeginHold
    }

    mutating func cancel() -> LauncherSpaceKeyDecision {
        let wasHolding = isHolding
        isPendingHold = false
        isHolding = false
        return wasHolding ? .sendEndHold : .pass
    }
}

@available(macOS 26.0, *)
struct LauncherWindowDismissalPolicy {
    static func shouldHideOnResignKey(mode: LauncherMode, isPinned: Bool, isShowingSettings: Bool = false) -> Bool {
        if isShowingSettings {
            return true
        }
        return !isPinned && mode != .files
    }
}

@available(macOS 26.0, *)
extension LiquidGlassLauncherWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        model.setWindowKeyState(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        model.setWindowKeyState(false)

        guard window.isVisible,
              window.attachedSheet == nil,
              LauncherWindowDismissalPolicy.shouldHideOnResignKey(
                  mode: model.mode,
                  isPinned: model.isPinned,
                  isShowingSettings: model.isShowingSettings
              ) else {
            return
        }
        hide()
    }
}
