import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class LauncherWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let panel: FloatingPanel
    private let searchField = LauncherSearchField()
    private let indexingIndicator = NSProgressIndicator()
    private let controlsStack = NSStackView()
    private let clearHistoryButton = NSButton(title: "", target: nil, action: nil)
    private let pinButton = NSButton(title: "", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let resizeGripView = ResizeGripView()
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let calculationHistoryStore: CalculationHistoryStore
    private let openSettingsAction: () -> Void

    private var mode: LauncherMode = .applications
    private var allItems: [LaunchItem] = []
    private var filteredItems: [LaunchItem] = []
    private var toolItems: [ToolItem] = []
    private var isIndexing = false
    private var needsReindexAfterCurrent = false
    private var pendingCalculationHistoryTimer: Timer?
    private var pendingCalculationHistoryExpression: String?
    private var pendingCalculationHistoryResult: String?
    private var localKeyMonitor: Any?
    private var isPinned = false
    private var applicationQuery = ""
    private var toolsQuery = ""

    init(
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        openSettingsAction: @escaping () -> Void
    ) {
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.calculationHistoryStore = calculationHistoryStore
        self.openSettingsAction = openSettingsAction
        let contentRect = NSRect(x: 0, y: 0, width: 720, height: 430)
        panel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        buildWindow()
        installLocalKeyMonitor()
        reindex()
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func toggle() {
        if isPinned {
            focusPinnedWindow()
            return
        }

        if panel.isVisible && mode == .applications {
            hide()
        } else {
            show()
        }
    }

    func show() {
        show(mode: .applications)
    }

    private func show(mode: LauncherMode) {
        applicationQuery = ""
        toolsQuery = ""
        self.mode = mode
        updateModeChrome()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        searchField.stringValue = storedQuery(for: mode)
        applyCurrentMode()
        searchField.becomeFirstResponder()

        if mode == .applications {
            DispatchQueue.main.async { [weak self] in
                self?.reindex()
            }
        }
    }

    func hide() {
        cancelPendingCalculationHistory()
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        panel.resignKey()
        panel.invalidateCursorRects(for: panel.contentView ?? NSView())
        NSCursor.arrow.set()
    }

    func reindex() {
        guard !isIndexing else {
            needsReindexAfterCurrent = true
            setIndexing(true)
            return
        }

        isIndexing = true
        needsReindexAfterCurrent = false
        inclusionStore.load()
        exclusionStore.load()
        if mode == .applications {
            setIndexing(true)
            updateEmptyState(query: searchField.stringValue)
        }

        let includedPaths = inclusionStore.includedPaths
        DispatchQueue.global(qos: .userInitiated).async {
            let items = ApplicationIndexer().load(includedPaths: includedPaths)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.allItems = items
                self.isIndexing = false

                if self.needsReindexAfterCurrent {
                    self.reindex()
                    if self.mode == .applications {
                        self.applyFilter()
                    }
                } else {
                    if self.mode == .applications {
                        self.setIndexing(false)
                        self.applyFilter()
                    }
                }
            }
        }
    }

    private func buildWindow() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 360, height: 300)
        panel.commandHandler = { [weak self] command in
            self?.handle(command: command) ?? false
        }

        let rootView = buildRootView()

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.placeholderString = "Search for Apps"
        searchField.font = .systemFont(ofSize: 18, weight: .medium)
        searchField.focusRingType = .none
        searchField.commandHandler = { [weak self] command in
            self?.handle(command: command) ?? false
        }

        indexingIndicator.translatesAutoresizingMaskIntoConstraints = false
        indexingIndicator.style = .spinning
        indexingIndicator.controlSize = .small
        indexingIndicator.isIndeterminate = true
        indexingIndicator.isDisplayedWhenStopped = false
        indexingIndicator.isHidden = true

        clearHistoryButton.translatesAutoresizingMaskIntoConstraints = false
        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistoryClicked)
        applyPreferredButtonBezelStyle(clearHistoryButton)
        clearHistoryButton.setButtonType(.momentaryPushIn)
        clearHistoryButton.toolTip = "Clear calculation history"
        clearHistoryButton.isHidden = true
        if let image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear history") {
            clearHistoryButton.image = image
            clearHistoryButton.imagePosition = .imageOnly
        } else {
            clearHistoryButton.title = "Clear"
        }

        pinButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        applyPreferredButtonBezelStyle(pinButton)
        pinButton.setButtonType(.toggle)
        pinButton.toolTip = "Pin window (Command+P)"
        if let image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin") {
            pinButton.image = image
            pinButton.imagePosition = .imageOnly
        } else {
            pinButton.title = "Pin"
        }

        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 6
        controlsStack.detachesHiddenViews = true
        controlsStack.addArrangedSubview(indexingIndicator)
        controlsStack.addArrangedSubview(clearHistoryButton)
        controlsStack.addArrangedSubview(pinButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.backgroundColor = .clear
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelected)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ResultColumn"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 0
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.isHidden = true

        resizeGripView.translatesAutoresizingMaskIntoConstraints = false
        resizeGripView.resizeHandler = { [weak self] in
            self?.panel.contentView?.layoutSubtreeIfNeeded()
            self?.resizeResultColumn()
        }

        rootView.addSubview(searchField)
        rootView.addSubview(controlsStack)
        rootView.addSubview(scrollView)
        rootView.addSubview(emptyLabel)
        rootView.addSubview(resizeGripView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: controlsStack.leadingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 42),

            controlsStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            controlsStack.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            indexingIndicator.widthAnchor.constraint(equalToConstant: 18),
            indexingIndicator.heightAnchor.constraint(equalToConstant: 18),
            clearHistoryButton.widthAnchor.constraint(equalToConstant: 30),
            clearHistoryButton.heightAnchor.constraint(equalToConstant: 26),
            pinButton.widthAnchor.constraint(equalToConstant: 30),
            pinButton.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -18),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            resizeGripView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -4),
            resizeGripView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -2),
            resizeGripView.widthAnchor.constraint(equalToConstant: 22),
            resizeGripView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func buildRootView() -> NSView {
        if #available(macOS 26.0, *) {
            return buildLiquidGlassRootView()
        }

        let rootView = NSVisualEffectView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.material = .hudWindow
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 8
        rootView.layer?.masksToBounds = true
        panel.contentView = rootView
        return rootView
    }

    @available(macOS 26.0, *)
    private func buildLiquidGlassRootView() -> NSView {
        let glassView = NSGlassEffectView()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.style = .regular
        glassView.cornerRadius = 8
        panel.contentView = glassView

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 8
        rootView.layer?.masksToBounds = true
        glassView.contentView = rootView

        NSLayoutConstraint.activate([
            rootView.topAnchor.constraint(equalTo: glassView.topAnchor),
            rootView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            rootView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
        ])

        return rootView
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel.isVisible,
                  self.panel.isKeyWindow || self.panel.isMainWindow else {
                return event
            }

            if event.isToolsShortcut {
                return self.handle(command: .toggleToolsMode) ? nil : event
            }
            if event.isCommandP {
                return self.handle(command: .togglePin) ? nil : event
            }

            return event
        }
    }

    private func updateModeChrome() {
        switch mode {
        case .applications:
            searchField.placeholderString = "Search for Apps"
            clearHistoryButton.isHidden = true
            if isIndexing {
                setIndexing(true)
            } else {
                setIndexing(false)
            }
        case .tools:
            searchField.placeholderString = "Calculate Numbers and Define Words"
            setIndexing(false)
            clearHistoryButton.isHidden = false
        }
        updatePinButton()
        updateClearHistoryButton()
    }

    private var inputIsBlank: Bool {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func clearHistoryClicked() {
        calculationHistoryStore.clear()
        applyToolsResults(scheduleHistory: false)
        searchField.becomeFirstResponder()
    }

    @objc private func pinClicked() {
        setPinned(!isPinned)
        searchField.becomeFirstResponder()
    }

    private func setPinned(_ pinned: Bool) {
        guard isPinned != pinned else {
            updatePinButton()
            return
        }

        isPinned = pinned
        panel.isMovableByWindowBackground = pinned
        panel.level = pinned ? .statusBar : .floating
        updatePinButton()
    }

    private func focusPinnedWindow() {
        guard panel.isVisible else {
            show()
            return
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        searchField.becomeFirstResponder()
    }

    private func updatePinButton() {
        pinButton.state = isPinned ? .on : .off
        pinButton.toolTip = isPinned ? "Unpin window (Command+P)" : "Pin window (Command+P)"

        let symbolName = isPinned ? "pin.fill" : "pin"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            pinButton.image = image
            pinButton.imagePosition = .imageOnly
        }
    }

    private func updateClearHistoryButton() {
        clearHistoryButton.isEnabled = mode == .tools && !calculationHistoryStore.calculations.isEmpty
    }

    private func toggleToolsMode() -> Bool {
        switch mode {
        case .applications:
            switchMode(to: .tools)
        case .tools:
            switchMode(to: .applications)
        }

        return true
    }

    private func switchMode(to nextMode: LauncherMode) {
        guard mode != nextMode else { return }

        storeCurrentQuery()
        mode = nextMode
        searchField.stringValue = storedQuery(for: nextMode)
        updateModeChrome()
        applyCurrentMode()
        searchField.becomeFirstResponder()

        if nextMode == .applications {
            DispatchQueue.main.async { [weak self] in
                self?.reindex()
            }
        }
    }

    private func applyCurrentMode() {
        switch mode {
        case .applications:
            cancelPendingCalculationHistory()
            applyFilter()
        case .tools:
            calculationHistoryStore.load()
            applyToolsResults()
        }
    }

    private func applyToolsResults(scheduleHistory: Bool = true) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelPendingCalculationHistory()

        if query.isEmpty {
            toolItems = calculationHistoryItems()
        } else if ArithmeticEvaluator.isArithmeticInput(query) {
            if let result = ArithmeticEvaluator.evaluate(query) {
                toolItems = [
                    ToolItem(
                        title: result,
                        subtitle: "\(query) =",
                        copyText: result,
                        kind: .calculation
                    )
                ] + calculationHistoryItems(excludingExpression: query, result: result)

                if scheduleHistory, ArithmeticEvaluator.shouldStoreInHistory(query) {
                    scheduleCalculationHistory(expression: query, result: result)
                }
            } else {
                toolItems = [
                    ToolItem(
                        title: "Complete the calculation",
                        subtitle: query,
                        copyText: nil,
                        kind: .message
                    )
                ] + calculationHistoryItems()
            }
        } else {
            let dictionaryResults = DictionaryLookup.results(for: query)

            if !dictionaryResults.isEmpty {
                toolItems = dictionaryResults.map { result in
                    ToolItem(
                        title: result.term,
                        subtitle: Self.singleLine(result.definition),
                        copyText: nil,
                        kind: .dictionary
                    )
                }
            } else {
                toolItems = [
                    ToolItem(
                        title: "No dictionary matches",
                        subtitle: query,
                        copyText: nil,
                        kind: .message
                    )
                ]
            }
        }

        resizeResultColumn()
        tableView.reloadData()
        selectFirstResult()
        updateToolsEmptyState(query: query)
        updateClearHistoryButton()
    }

    private func calculationHistoryItems(
        excludingExpression expression: String? = nil,
        result excludedResult: String? = nil
    ) -> [ToolItem] {
        calculationHistoryStore.calculations.compactMap { entry in
            if entry.expression == expression && entry.result == excludedResult {
                return nil
            }

            return ToolItem(
                title: "\(entry.expression) = \(entry.result)",
                subtitle: "Calculated \(Self.calculationHistoryDateFormatter.string(from: entry.date))",
                copyText: entry.result,
                kind: .calculationHistory
            )
        }
    }

    private func scheduleCalculationHistory(expression: String, result: String) {
        pendingCalculationHistoryExpression = expression
        pendingCalculationHistoryResult = result
        pendingCalculationHistoryTimer = Timer.scheduledTimer(
            withTimeInterval: 0.7,
            repeats: false
        ) { [weak self] _ in
            self?.commitPendingCalculationHistory(refreshResults: true)
        }
    }

    private func commitPendingCalculationHistory(refreshResults: Bool) {
        guard let expression = pendingCalculationHistoryExpression,
              let result = pendingCalculationHistoryResult else {
            return
        }

        cancelPendingCalculationHistory()
        calculationHistoryStore.add(expression: expression, result: result)

        if refreshResults, mode == .tools {
            applyToolsResults(scheduleHistory: false)
        }
    }

    private func cancelPendingCalculationHistory() {
        pendingCalculationHistoryTimer?.invalidate()
        pendingCalculationHistoryTimer = nil
        pendingCalculationHistoryExpression = nil
        pendingCalculationHistoryResult = nil
    }

    private func updateToolsEmptyState(query: String) {
        if toolItems.isEmpty {
            emptyLabel.stringValue = query.isEmpty ? "No calculation history" : "No tool results"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private static let calculationHistoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func singleLine(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func setIndexing(_ indexing: Bool) {
        if indexing {
            indexingIndicator.isHidden = false
            indexingIndicator.startAnimation(nil)
        } else {
            indexingIndicator.stopAnimation(nil)
            indexingIndicator.isHidden = true
        }
    }

    private func positionPanel() {
        guard let screen = Self.primaryScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(720, max(360, visibleFrame.width - 40))
        let height = min(430, max(300, visibleFrame.height - 80))
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.maxY - height - 96
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        resizeResultColumn()
    }

    static func primaryScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == mainDisplayID
        }
    }

    private func resizeResultColumn() {
        guard let column = tableView.tableColumns.first else { return }
        let fallbackWidth = panel.contentView?.bounds.width ?? panel.frame.width
        let width = max(0, scrollView.contentSize.width > 0 ? scrollView.contentSize.width : fallbackWidth)
        column.width = width
        tableView.frame.size.width = width
    }

    private func applyFilter(preservePreviousOnEmpty: Bool = false) {
        let query = searchField.stringValue
        let visibleItems = allItems.filter { !exclusionStore.isExcluded($0) }
        let nextItems = Self.filter(visibleItems, query: query)

        if preservePreviousOnEmpty,
           nextItems.isEmpty,
           !filteredItems.isEmpty,
           !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyLabel.isHidden = true
            return
        }

        filteredItems = nextItems
        resizeResultColumn()
        tableView.reloadData()
        selectFirstResult()
        updateEmptyState(query: query)
    }

    private static func filter(_ items: [LaunchItem], query: String) -> [LaunchItem] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else {
            return Array(items.prefix(80))
        }

        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return items.compactMap { item -> (LaunchItem, Int)? in
            guard tokens.allSatisfy({ item.searchText.contains($0) }) else {
                return nil
            }

            let title = normalized(item.title)
            var score = 0

            for token in tokens {
                if title == token {
                    score += 1200
                } else if title.hasPrefix(token) {
                    score += 1000
                } else if title.split(separator: " ").contains(where: { $0.hasPrefix(token) }) {
                    score += 850
                } else if title.contains(token) {
                    score += 650
                } else {
                    score += 350
                }
            }

            score -= min(item.title.count, 120)
            return (item, score)
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
            }
            return $0.1 > $1.1
        }
        .prefix(80)
        .map(\.0)
    }

    private var displayedResultCount: Int {
        switch mode {
        case .applications:
            return filteredItems.count
        case .tools:
            return toolItems.count
        }
    }

    private func selectFirstResult() {
        guard displayedResultCount > 0 else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    private func updateEmptyState(query: String) {
        if filteredItems.isEmpty {
            if isIndexing && allItems.isEmpty {
                emptyLabel.stringValue = "Loading apps"
            } else {
                emptyLabel.stringValue = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "No launchable items found"
                    : "No matches"
            }
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private func handle(command: LauncherCommand) -> Bool {
        switch command {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
        case .top:
            moveSelection(to: 0)
        case .bottom:
            moveSelection(to: displayedResultCount - 1)
        case .open:
            openSelected()
        case .close:
            clearInputOrHide()
        case .reindex:
            reindex()
        case .settings:
            openSettingsAction()
        case .toggleToolsMode:
            return toggleToolsMode()
        case .clearHistory:
            clearHistoryClicked()
        case .togglePin:
            pinClicked()
        }
        return true
    }

    private func clearInputOrHide() {
        if inputIsBlank {
            if isPinned {
                setPinned(false)
            }
            hide()
            return
        }

        searchField.stringValue = ""
        storeCurrentQuery()
        applyCurrentMode()
        searchField.becomeFirstResponder()
    }

    private func storeCurrentQuery() {
        switch mode {
        case .applications:
            applicationQuery = searchField.stringValue
        case .tools:
            toolsQuery = searchField.stringValue
        }
    }

    private func storedQuery(for mode: LauncherMode) -> String {
        switch mode {
        case .applications:
            return applicationQuery
        case .tools:
            return toolsQuery
        }
    }

    private func moveSelection(by delta: Int) {
        let count = displayedResultCount
        guard count > 0 else { return }
        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = max(0, min(count - 1, current + delta))
        moveSelection(to: next)
    }

    private func moveSelection(to row: Int) {
        let count = displayedResultCount
        guard count > 0 else { return }
        let next = max(0, min(count - 1, row))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func openSelected() {
        let row = tableView.selectedRow
        switch mode {
        case .applications:
            guard row >= 0, row < filteredItems.count else { return }
            let item = filteredItems[row]
            if !isPinned {
                hide()
            }
            launch(item)
        case .tools:
            guard row >= 0, row < toolItems.count else { return }
            activate(toolItems[row])
        }
    }

    private func launch(_ item: LaunchItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: configuration) { _, error in
            if let error {
                NSLog("Bucky failed to open %@: %@", item.url.path, error.localizedDescription)
            }
        }
    }

    private func exclude(_ item: LaunchItem) {
        exclusionStore.exclude(item)
        applyFilter()
    }

    private func activate(_ item: ToolItem) {
        switch item.kind {
        case .calculation:
            commitPendingCalculationHistory(refreshResults: false)
            copyToPasteboard(item.copyText)
        case .calculationHistory:
            copyToPasteboard(item.copyText)
        case .dictionary:
            openDictionary(term: item.title)
        case .message:
            return
        }

        if !isPinned {
            hide()
        }
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func openDictionary(term: String) {
        guard let escapedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://\(escapedTerm)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refreshAfterExclusionsChanged() {
        if mode == .applications {
            applyFilter()
        }
    }

    func refreshAfterInclusionsChanged() {
        reindex()
    }

    func refreshAfterSettingsChanged() {
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedResultCount
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        54
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCellView.reuseIdentifier, owner: self) as? ResultCellView
            ?? ResultCellView(frame: .zero)

        switch mode {
        case .applications:
            let item = filteredItems[row]
            cell.configure(with: item) { [weak self] in
                self?.exclude(item)
            }
        case .tools:
            cell.configure(with: toolItems[row])
        }
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        storeCurrentQuery()

        switch mode {
        case .applications:
            applyFilter(preservePreviousOnEmpty: true)
        case .tools:
            applyToolsResults()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            return handle(command: .up)
        case #selector(NSResponder.moveDown(_:)):
            return handle(command: .down)
        case #selector(NSResponder.moveToBeginningOfDocument(_:)):
            return handle(command: .top)
        case #selector(NSResponder.moveToEndOfDocument(_:)):
            return handle(command: .bottom)
        case #selector(NSResponder.insertNewline(_:)):
            return handle(command: .open)
        case #selector(NSResponder.cancelOperation(_:)):
            return handle(command: .close)
        default:
            return false
        }
    }
}
