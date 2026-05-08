import AppKit
import Carbon
import SwiftUI

@available(macOS 26.0, *)
final class LiquidGlassLauncherWindowController: NSObject, LauncherControlling {
    private let window: LiquidGlassWindow
    private let model: LiquidGlassLauncherModel
    private var localKeyMonitor: Any?
    private var applicationActivationObserver: NSObjectProtocol?
    private var quickLookPreviewPanel: NSPanel?
    private var quickLookPreviewHost: NSHostingController<QuickLookPreviewSurface>?
    private var spaceKeyRouter = LauncherSpaceKeyRouter()
    private var pendingSpaceHoldTimer: Timer?
    private var isOptionPinnedFocusActive = false
    private var visibilityState: WindowVisibilityState = .hidden
    private var visibilityTransitionID = 0
    private var presentationAnimation: Animation {
        model.animationTiming.animation(duration: 0.24)
    }

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        openSettingsAction: @escaping () -> Void
    ) {
        model = LiquidGlassLauncherModel(
            settingsStore: settingsStore,
            inclusionStore: inclusionStore,
            exclusionStore: exclusionStore,
            calculationHistoryStore: calculationHistoryStore
        )
        window = LiquidGlassWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        model.hideAction = { [weak self] in self?.hide() }
        model.openSettingsAction = openSettingsAction
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
        reindex()
    }

    deinit {
        cancelSpaceHoldState(deliverEndHold: true)
        cancelOptionPinnedFocus()
        closeQuickLookPreviewPanel()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let applicationActivationObserver {
            NotificationCenter.default.removeObserver(applicationActivationObserver)
        }
    }

    func toggle() {
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

    private func show(mode: LauncherMode) {
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
        let transitionID = visibilityTransitionID

        if shouldMaterialize {
            withAnimation(presentationAnimation, completionCriteria: .logicallyComplete) {
                model.isPresented = true
            } completion: { [weak self] in
                self?.finishShow(transitionID: transitionID)
            }
        } else {
            finishShow(transitionID: transitionID)
        }

        if mode == .applications {
            DispatchQueue.main.async { [weak self] in
                self?.reindex()
            }
        }
    }

    private func hide() {
        guard visibilityState != .hidden,
              visibilityState != .hiding else {
            return
        }

        beginVisibilityTransition(.hiding)
        closeQuickLookPreviewPanel()
        cancelSpaceHoldState(deliverEndHold: true)
        cancelOptionPinnedFocus()
        model.cancelPendingCalculationHistory()

        let transitionID = visibilityTransitionID
        withAnimation(presentationAnimation, completionCriteria: .removed) {
            model.isPresented = false
        } completion: { [weak self] in
            self?.finishHide(transitionID: transitionID)
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

    private func buildWindow() {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = LauncherWindowDragPolicy.isMovableByWindowBackground
        window.minSize = NSSize(width: 520, height: 340)
        window.delegate = self
        window.commandHandler = { [weak self] command in
            self?.handleLauncherCommand(command) ?? false
        }

        let hostingView = NSHostingView(rootView: LiquidGlassLauncherView(model: model))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
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

            if LauncherKeyRoutingPolicy.shouldPassThroughFileTextEditing(
                mode: self.model.mode,
                fileFocusState: self.model.mode == .files ? self.fileBrowserFocusState : nil,
                keyCode: event.keyCode,
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

    private func handleLauncherCommand(_ command: LauncherCommand) -> Bool {
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
            guard let self else { return }
            self.pendingSpaceHoldTimer = nil
            _ = self.performSpaceKeyDecision(
                self.spaceKeyRouter.holdDelayElapsed(),
                event: nil
            )
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
        guard let screen = primaryDisplayScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = LauncherWindowFramePolicy.frame(
            mode: model.mode,
            fileFocusState: model.mode == .files ? fileBrowserFocusState : nil,
            visibleFrame: visibleFrame
        )

        guard window.frame != frame else { return }
        window.setFrame(frame, display: true, animate: animated)
    }

    private func syncQuickLookPreviewPanel() {
        guard model.mode == .files,
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
    static func shouldHideOnResignKey(mode: LauncherMode, isPinned: Bool) -> Bool {
        !isPinned && mode != .files
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
              LauncherWindowDismissalPolicy.shouldHideOnResignKey(mode: model.mode, isPinned: model.isPinned) else {
            return
        }
        hide()
    }
}

@available(macOS 26.0, *)
private final class LiquidGlassWindow: NSWindow {
    var commandHandler: ((LauncherCommand) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let mode = event.commandNumberMode, commandHandler?(.switchMode(mode)) == true {
            return true
        }
        if event.isCommandR, commandHandler?(.reindex) == true {
            return true
        }
        if event.isCommandComma, commandHandler?(.settings) == true {
            return true
        }
        if event.isCommandP, commandHandler?(.togglePin) == true {
            return true
        }
        if event.isCommandLeftBracket, commandHandler?(.historyBack) == true {
            return true
        }
        if event.isCommandRightBracket, commandHandler?(.historyForward) == true {
            return true
        }
        if event.isCommandUpArrow, commandHandler?(.top) == true {
            return true
        }
        if event.isCommandDownArrow, commandHandler?(.bottom) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if commandHandler?(.close) != true {
            orderOut(sender)
        }
    }
}
