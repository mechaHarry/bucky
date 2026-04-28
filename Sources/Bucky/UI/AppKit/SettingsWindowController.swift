import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsViewModel
    private var hotKeyEventMonitor: Any?

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        hotKeyChangeHandler: @escaping (HotKeyConfiguration) -> Bool,
        inclusionsChangedHandler: @escaping () -> Void,
        exclusionsChangedHandler: @escaping () -> Void
    ) {
        model = SettingsViewModel(
            settingsStore: settingsStore,
            inclusionStore: inclusionStore,
            exclusionStore: exclusionStore,
            hotKeyChangeHandler: hotKeyChangeHandler,
            inclusionsChangedHandler: inclusionsChangedHandler,
            exclusionsChangedHandler: exclusionsChangedHandler
        )

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bucky Settings"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        window.closeAction = { [weak self] in
            self?.closeSettings()
        }
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        hostingView.sizingOptions = []
        window.contentView = hostingView

        model.startHotKeyRecordingAction = { [weak self] in
            self?.startRecordingHotKey()
        }
        model.presentIncludedAppPickerAction = { [weak self] in
            self?.presentIncludedAppPicker()
        }

        model.refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        stopRecordingHotKey()
    }

    func show() {
        model.refresh()
        positionWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard window?.attachedSheet == nil else { return }
        closeSettings()
    }

    func windowWillClose(_ notification: Notification) {
        stopRecordingHotKey()
    }

    private func closeSettings() {
        stopRecordingHotKey()
        window?.orderOut(nil)
    }

    private func startRecordingHotKey() {
        stopRecordingHotKey(resetModel: false)

        hotKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.closeSettings()
                return nil
            }

            guard let hotKey = HotKeyConfiguration(event: event) else {
                NSSound.beep()
                return nil
            }

            self.model.commitHotKey(hotKey)
            self.stopRecordingHotKey(resetModel: false)
            return nil
        }
    }

    private func stopRecordingHotKey(resetModel: Bool = true) {
        if let hotKeyEventMonitor {
            NSEvent.removeMonitor(hotKeyEventMonitor)
            self.hotKeyEventMonitor = nil
        }

        if resetModel {
            model.cancelHotKeyRecording()
        }
    }

    private func presentIncludedAppPicker() {
        guard let window else { return }

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
            self?.model.addIncludedApps(panel.urls)
        }
    }

    private func positionWindow() {
        guard let window,
              let screen = LauncherWindowController.primaryScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            window?.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.midY - frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class SettingsWindow: NSWindow {
    var closeAction: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        closeAction?()
    }
}
