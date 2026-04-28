import AppKit
import Carbon
import CoreGraphics
import CoreServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
final class LiquidGlassLauncherWindowController: NSObject, LauncherControlling {
    private let window: LiquidGlassWindow
    private let model: LiquidGlassLauncherModel
    private var localKeyMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?
    private var visibilityState: WindowVisibilityState = .hidden
    private var visibilityTransitionID = 0

    init(
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        openSettingsAction: @escaping () -> Void
    ) {
        model = LiquidGlassLauncherModel(
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
        buildWindow()
        installLocalKeyMonitor()
        reindex()
    }

    deinit {
        hideWorkItem?.cancel()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func toggle() {
        guard !model.isPinned else { return }

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
        hideWorkItem?.cancel()
        hideWorkItem = nil
        model.show(mode: mode)
        model.isPresented = false
        positionWindow()
        if !window.isVisible {
            window.alphaValue = 0
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        withAnimation(.interactiveSpring(duration: 0.2, extraBounce: 0.04)) {
            model.isPresented = true
        }
        let transitionID = visibilityTransitionID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self,
                  self.visibilityTransitionID == transitionID,
                  self.visibilityState == .showing else {
                return
            }
            self.visibilityState = .shown
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
        hideWorkItem?.cancel()
        model.cancelPendingCalculationHistory()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }

        let transitionID = visibilityTransitionID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.visibilityTransitionID == transitionID,
                  self.visibilityState == .hiding else {
                return
            }
            self.window.makeFirstResponder(nil)
            self.window.orderOut(nil)
            self.window.resignKey()
            self.window.alphaValue = 1
            self.model.isPresented = false
            self.visibilityState = .hidden
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: workItem)
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

    private func buildWindow() {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 520, height: 340)
        window.delegate = self
        window.commandHandler = { [weak model] command in
            model?.handle(command: command) ?? false
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

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.window.isVisible,
                  self.window.isKeyWindow || self.window.isMainWindow else {
                return event
            }

            if event.isCommandR {
                return self.model.handle(command: .reindex) ? nil : event
            }
            if event.isCommandComma {
                return self.model.handle(command: .settings) ? nil : event
            }
            if event.isToolsShortcut {
                return self.model.handle(command: .toggleToolsMode) ? nil : event
            }
            if event.isCommandUpArrow {
                return self.model.handle(command: .top) ? nil : event
            }
            if event.isCommandDownArrow {
                return self.model.handle(command: .bottom) ? nil : event
            }

            switch event.keyCode {
            case 126:
                return self.model.handle(command: .up) ? nil : event
            case 125:
                return self.model.handle(command: .down) ? nil : event
            case 36, 76:
                return self.model.handle(command: .open) ? nil : event
            case 53:
                return self.model.handle(command: .close) ? nil : event
            default:
                return event
            }
        }
    }

    private func positionWindow() {
        guard let screen = LauncherWindowController.primaryScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let width = min(760, max(520, visibleFrame.width - 120))
        let height = min(460, max(340, visibleFrame.height - 120))
        let frame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )

        window.setFrame(frame, display: true)
    }

    private func setPinned(_ isPinned: Bool) {
        window.level = isPinned ? .statusBar : .floating
    }

    private func beginVisibilityTransition(_ state: WindowVisibilityState) {
        visibilityTransitionID += 1
        visibilityState = state
    }
}

@available(macOS 26.0, *)
private enum WindowVisibilityState {
    case hidden
    case showing
    case shown
    case hiding
}

@available(macOS 26.0, *)
extension LiquidGlassLauncherWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard window.isVisible, !model.isPinned else { return }
        hide()
    }
}

@available(macOS 26.0, *)
private final class LiquidGlassWindow: NSWindow {
    var commandHandler: ((LauncherCommand) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isCommandR, commandHandler?(.reindex) == true {
            return true
        }
        if event.isCommandComma, commandHandler?(.settings) == true {
            return true
        }
        if event.isToolsShortcut, commandHandler?(.toggleToolsMode) == true {
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
