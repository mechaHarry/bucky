import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let settingsStore: SettingsStore
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let hotKeyChangeHandler: (HotKeyConfiguration) -> Bool
    private let inclusionsChangedHandler: () -> Void
    private let exclusionsChangedHandler: () -> Void

    private let hotKeyButton = NSButton(title: "", target: nil, action: nil)
    private let launchAtStartupCheckbox = NSButton(checkboxWithTitle: "Launch on startup", target: nil, action: nil)
    private let inclusionsTableView = NSTableView()
    private let addInclusionButton = NSButton(title: "Add...", target: nil, action: nil)
    private let removeInclusionButton = NSButton(title: "Remove", target: nil, action: nil)
    private let exclusionsTableView = NSTableView()
    private let removeExclusionButton = NSButton(title: "Remove", target: nil, action: nil)
    private var inclusionPaths: [String] = []
    private var exclusionPaths: [String] = []
    private var hotKeyEventMonitor: Any?
    private var isRecordingHotKey = false

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        hotKeyChangeHandler: @escaping (HotKeyConfiguration) -> Bool,
        inclusionsChangedHandler: @escaping () -> Void,
        exclusionsChangedHandler: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.hotKeyChangeHandler = hotKeyChangeHandler
        self.inclusionsChangedHandler = inclusionsChangedHandler
        self.exclusionsChangedHandler = exclusionsChangedHandler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bucky Settings"
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildWindow()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        stopRecordingHotKey()
    }

    func show() {
        refresh()
        positionWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        guard let contentView = window?.contentView else { return }

        let rootStack = NSStackView()
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        contentView.addSubview(rootStack)

        let hotKeyLabel = NSTextField(labelWithString: "Hotkey")
        hotKeyLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        hotKeyButton.translatesAutoresizingMaskIntoConstraints = false
        hotKeyButton.target = self
        hotKeyButton.action = #selector(startRecordingHotKey)
        hotKeyButton.bezelStyle = .rounded
        hotKeyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let hotKeyRow = NSStackView(views: [hotKeyLabel, hotKeyButton])
        hotKeyRow.translatesAutoresizingMaskIntoConstraints = false
        hotKeyRow.orientation = .horizontal
        hotKeyRow.alignment = .centerY
        hotKeyRow.spacing = 12

        launchAtStartupCheckbox.translatesAutoresizingMaskIntoConstraints = false
        launchAtStartupCheckbox.target = self
        launchAtStartupCheckbox.action = #selector(launchAtStartupChanged)

        let inclusionsLabel = NSTextField(labelWithString: "Included apps")
        inclusionsLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let inclusionsScrollView = NSScrollView()
        inclusionsScrollView.translatesAutoresizingMaskIntoConstraints = false
        inclusionsScrollView.hasVerticalScroller = true
        inclusionsScrollView.autohidesScrollers = true
        inclusionsScrollView.hasHorizontalScroller = false
        inclusionsScrollView.borderType = .bezelBorder

        inclusionsTableView.translatesAutoresizingMaskIntoConstraints = false
        inclusionsTableView.headerView = nil
        inclusionsTableView.rowHeight = 28
        inclusionsTableView.usesAlternatingRowBackgroundColors = true
        inclusionsTableView.allowsEmptySelection = true
        inclusionsTableView.delegate = self
        inclusionsTableView.dataSource = self

        let inclusionsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("IncludedPathColumn"))
        inclusionsColumn.resizingMask = .autoresizingMask
        inclusionsTableView.addTableColumn(inclusionsColumn)
        inclusionsScrollView.documentView = inclusionsTableView

        addInclusionButton.translatesAutoresizingMaskIntoConstraints = false
        addInclusionButton.target = self
        addInclusionButton.action = #selector(addIncludedApp)
        addInclusionButton.bezelStyle = .rounded

        removeInclusionButton.translatesAutoresizingMaskIntoConstraints = false
        removeInclusionButton.target = self
        removeInclusionButton.action = #selector(removeSelectedInclusion)
        removeInclusionButton.bezelStyle = .rounded

        let inclusionsButtonsRow = NSStackView(views: [addInclusionButton, removeInclusionButton])
        inclusionsButtonsRow.translatesAutoresizingMaskIntoConstraints = false
        inclusionsButtonsRow.orientation = .horizontal
        inclusionsButtonsRow.alignment = .centerY
        inclusionsButtonsRow.spacing = 8

        let inclusionsStack = NSStackView(views: [inclusionsLabel, inclusionsScrollView, inclusionsButtonsRow])
        inclusionsStack.translatesAutoresizingMaskIntoConstraints = false
        inclusionsStack.orientation = .vertical
        inclusionsStack.alignment = .leading
        inclusionsStack.spacing = 8

        let exclusionsLabel = NSTextField(labelWithString: "Hidden apps")
        exclusionsLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        exclusionsTableView.translatesAutoresizingMaskIntoConstraints = false
        exclusionsTableView.headerView = nil
        exclusionsTableView.rowHeight = 28
        exclusionsTableView.usesAlternatingRowBackgroundColors = true
        exclusionsTableView.allowsEmptySelection = true
        exclusionsTableView.delegate = self
        exclusionsTableView.dataSource = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PathColumn"))
        column.resizingMask = .autoresizingMask
        exclusionsTableView.addTableColumn(column)
        scrollView.documentView = exclusionsTableView

        removeExclusionButton.translatesAutoresizingMaskIntoConstraints = false
        removeExclusionButton.target = self
        removeExclusionButton.action = #selector(removeSelectedExclusion)
        removeExclusionButton.bezelStyle = .rounded

        let exclusionsStack = NSStackView(views: [exclusionsLabel, scrollView, removeExclusionButton])
        exclusionsStack.translatesAutoresizingMaskIntoConstraints = false
        exclusionsStack.orientation = .vertical
        exclusionsStack.alignment = .leading
        exclusionsStack.spacing = 8

        rootStack.addArrangedSubview(hotKeyRow)
        rootStack.addArrangedSubview(launchAtStartupCheckbox)
        rootStack.addArrangedSubview(inclusionsStack)
        rootStack.addArrangedSubview(exclusionsStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            hotKeyRow.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            hotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

            inclusionsStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            inclusionsScrollView.heightAnchor.constraint(equalToConstant: 150),
            inclusionsScrollView.leadingAnchor.constraint(equalTo: inclusionsStack.leadingAnchor),
            inclusionsScrollView.trailingAnchor.constraint(equalTo: inclusionsStack.trailingAnchor),
            addInclusionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            removeInclusionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),

            exclusionsStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 150),
            scrollView.leadingAnchor.constraint(equalTo: exclusionsStack.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: exclusionsStack.trailingAnchor),
            removeExclusionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
    }

    private func positionWindow() {
        guard let window, let screen = LauncherWindowController.primaryScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            window?.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.midY - frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func refresh() {
        settingsStore.load()
        inclusionStore.load()
        exclusionStore.load()
        hotKeyButton.title = settingsStore.settings.hotKey.displayName
        launchAtStartupCheckbox.state = settingsStore.settings.launchAtStartup ? .on : .off
        refreshInclusions()
        refreshExclusions()
    }

    private func refreshInclusions() {
        inclusionPaths = inclusionStore.sortedPaths()
        inclusionsTableView.reloadData()
        updateRemoveButtons()
    }

    private func refreshExclusions() {
        exclusionPaths = exclusionStore.sortedPaths()
        exclusionsTableView.reloadData()
        updateRemoveButtons()
    }

    @objc private func startRecordingHotKey() {
        guard !isRecordingHotKey else { return }
        isRecordingHotKey = true
        hotKeyButton.title = "Press shortcut"

        hotKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecordingHotKey else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecordingHotKey()
                self.hotKeyButton.title = self.settingsStore.settings.hotKey.displayName
                return nil
            }

            guard let hotKey = HotKeyConfiguration(event: event) else {
                NSSound.beep()
                return nil
            }

            if self.hotKeyChangeHandler(hotKey) {
                self.settingsStore.updateHotKey(hotKey)
                self.hotKeyButton.title = hotKey.displayName
            } else {
                self.hotKeyButton.title = self.settingsStore.settings.hotKey.displayName
            }

            self.stopRecordingHotKey()
            return nil
        }
    }

    private func stopRecordingHotKey() {
        isRecordingHotKey = false
        if let hotKeyEventMonitor {
            NSEvent.removeMonitor(hotKeyEventMonitor)
            self.hotKeyEventMonitor = nil
        }
    }

    @objc private func launchAtStartupChanged() {
        let enabled = launchAtStartupCheckbox.state == .on

        do {
            try LaunchAtStartupController.setEnabled(enabled)
            settingsStore.updateLaunchAtStartup(enabled)
        } catch {
            launchAtStartupCheckbox.state = settingsStore.settings.launchAtStartup ? .on : .off
            showError(title: "Could not update launch at startup", error: error)
        }
    }

    @objc private func addIncludedApp() {
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
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.inclusionStore.add(path: url.path)
            }
            self.refreshInclusions()
            self.inclusionsChangedHandler()
        }
    }

    @objc private func removeSelectedInclusion() {
        let row = inclusionsTableView.selectedRow
        guard row >= 0, row < inclusionPaths.count else { return }
        inclusionStore.remove(path: inclusionPaths[row])
        refreshInclusions()
        inclusionsChangedHandler()
    }

    @objc private func removeSelectedExclusion() {
        let row = exclusionsTableView.selectedRow
        guard row >= 0, row < exclusionPaths.count else { return }
        exclusionStore.remove(path: exclusionPaths[row])
        refreshExclusions()
        exclusionsChangedHandler()
    }

    private func updateRemoveButtons() {
        removeInclusionButton.isEnabled = inclusionsTableView.selectedRow >= 0
        removeExclusionButton.isEnabled = exclusionsTableView.selectedRow >= 0
    }

    private func showError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window ?? NSWindow())
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === inclusionsTableView {
            return inclusionPaths.count
        }
        return exclusionPaths.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = tableView === inclusionsTableView
            ? NSUserInterfaceItemIdentifier("InclusionCell")
            : NSUserInterfaceItemIdentifier("ExclusionCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.stringValue = tableView === inclusionsTableView
            ? inclusionPaths[row]
            : exclusionPaths[row]

        if cell.textField == nil {
            cell.identifier = identifier
            cell.textField = textField
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButtons()
    }
}
