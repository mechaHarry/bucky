import AppKit
import Carbon
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

private struct LaunchItem: Hashable {
    let title: String
    let subtitle: String
    let url: URL
    let searchText: String
}

private enum BuckyPaths {
    static var appSupportDirectory: URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportDirectory.appendingPathComponent("Bucky", isDirectory: true)
    }
}

private final class ApplicationIndexer {
    private let fileManager = FileManager.default
    private let roots = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
    ]

    func load(includedPaths: Set<String>) -> [LaunchItem] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .localizedNameKey
        ]

        var items: [LaunchItem] = []
        var seenPaths = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { url, error in
                    NSLog("Bucky index skipped %@: %@", url.path, error.localizedDescription)
                    return true
                }
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                let extensionName = url.pathExtension.lowercased()

                if extensionName == "app" {
                    if seenPaths.insert(url.path).inserted, let item = applicationItem(for: url) {
                        items.append(item)
                    }
                    enumerator.skipDescendants()
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                    continue
                }

                if values.isDirectory == true {
                    continue
                }
            }
        }

        for path in includedPaths.sorted() {
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.lowercased() == "app",
                  fileManager.fileExists(atPath: url.path),
                  seenPaths.insert(url.path).inserted,
                  let item = applicationItem(for: url) else {
                continue
            }
            items.append(item)
        }

        return items.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func applicationItem(for url: URL) -> LaunchItem? {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let executableName = bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        let bundleIdentifier = bundle?.bundleIdentifier
        let title = nonEmpty(displayName)
            ?? nonEmpty(bundleName)
            ?? url.deletingPathExtension().lastPathComponent

        let details = [
            bundleIdentifier,
            executableName,
            url.path
        ].compactMap { nonEmpty($0) }

        return LaunchItem(
            title: title,
            subtitle: url.path,
            url: url,
            searchText: normalized(([title] + details).joined(separator: " "))
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct ExclusionsFile: Codable {
    var excludedPaths: [String]
}

private struct InclusionsFile: Codable {
    var includedPaths: [String]
}

private struct HotKeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyName: String

    static let defaultValue = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        keyName: "Space"
    )

    var displayName: String {
        let modifierNames = carbonModifierDisplayNames(modifiers)
        guard !modifierNames.isEmpty else { return keyName }
        return (modifierNames + [keyName]).joined(separator: "+")
    }
}

private struct BuckySettings: Codable {
    var hotKey: HotKeyConfiguration
    var launchAtStartup: Bool

    static let defaultValue = BuckySettings(
        hotKey: .defaultValue,
        launchAtStartup: false
    )
}

private final class SettingsStore {
    private let fileManager = FileManager.default
    private(set) var settings: BuckySettings
    let fileURL: URL

    init() {
        fileURL = BuckyPaths.appSupportDirectory.appendingPathComponent("settings.json")
        settings = .defaultValue
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            settings = .defaultValue
            return
        }

        do {
            settings = try JSONDecoder().decode(BuckySettings.self, from: data)
        } catch {
            NSLog("Bucky could not read settings at %@: %@", fileURL.path, error.localizedDescription)
            settings = .defaultValue
        }
    }

    func updateHotKey(_ hotKey: HotKeyConfiguration) {
        settings.hotKey = hotKey
        save()
    }

    func updateLaunchAtStartup(_ enabled: Bool) {
        settings.launchAtStartup = enabled
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save settings at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

private final class ExclusionStore {
    private let fileManager = FileManager.default
    private(set) var excludedPaths = Set<String>()
    let fileURL: URL

    init() {
        fileURL = BuckyPaths.appSupportDirectory
            .appendingPathComponent("exclusions.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            excludedPaths = []
            return
        }

        do {
            let file = try JSONDecoder().decode(ExclusionsFile.self, from: data)
            excludedPaths = Set(file.excludedPaths)
        } catch {
            NSLog("Bucky could not read exclusions at %@: %@", fileURL.path, error.localizedDescription)
            excludedPaths = []
        }
    }

    func isExcluded(_ item: LaunchItem) -> Bool {
        excludedPaths.contains(item.url.path)
    }

    func exclude(_ item: LaunchItem) {
        excludedPaths.insert(item.url.path)
        save()
    }

    func remove(path: String) {
        excludedPaths.remove(path)
        save()
    }

    func sortedPaths() -> [String] {
        excludedPaths.sorted()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let file = ExclusionsFile(excludedPaths: excludedPaths.sorted())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save exclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

private final class InclusionStore {
    private let fileManager = FileManager.default
    private(set) var includedPaths = Set<String>()
    let fileURL: URL

    private static let defaultIncludedPaths: Set<String> = [
        "/System/Library/CoreServices/Finder.app"
    ]

    init() {
        fileURL = BuckyPaths.appSupportDirectory
            .appendingPathComponent("inclusions.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            includedPaths = Self.defaultIncludedPaths
            save()
            return
        }

        do {
            let file = try JSONDecoder().decode(InclusionsFile.self, from: data)
            includedPaths = Set(file.includedPaths)
        } catch {
            NSLog("Bucky could not read inclusions at %@: %@", fileURL.path, error.localizedDescription)
            includedPaths = Self.defaultIncludedPaths
            save()
        }
    }

    func add(path: String) {
        includedPaths.insert(path)
        save()
    }

    func remove(path: String) {
        includedPaths.remove(path)
        save()
    }

    func sortedPaths() -> [String] {
        includedPaths.sorted()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let file = InclusionsFile(includedPaths: includedPaths.sorted())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save inclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

private enum LauncherCommand {
    case up
    case down
    case open
    case close
    case reindex
    case settings
}

private final class LauncherSearchField: NSSearchField {
    var commandHandler: ((LauncherCommand) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isCommandR, commandHandler?(.reindex) == true {
            return true
        }
        if event.isCommandComma, commandHandler?(.settings) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            if commandHandler?(.up) == true { return }
        case 125:
            if commandHandler?(.down) == true { return }
        case 36, 76:
            if commandHandler?(.open) == true { return }
        case 53:
            if commandHandler?(.close) == true { return }
        default:
            break
        }

        super.keyDown(with: event)
    }
}

private final class FloatingPanel: NSPanel {
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
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if commandHandler?(.close) != true {
            orderOut(sender)
        }
    }
}

private final class ResultCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ResultCellView")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let excludeButton = NSButton(title: "", target: nil, action: nil)
    private var onExclude: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    func configure(with item: LaunchItem, onExclude: @escaping () -> Void) {
        self.onExclude = onExclude
        iconView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
        updateColors()
    }

    private func buildView() {
        identifier = Self.reuseIdentifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        excludeButton.translatesAutoresizingMaskIntoConstraints = false
        excludeButton.target = self
        excludeButton.action = #selector(excludeClicked)
        excludeButton.bezelStyle = .texturedRounded
        excludeButton.setButtonType(.momentaryPushIn)
        excludeButton.contentTintColor = .secondaryLabelColor
        excludeButton.toolTip = "Hide"
        excludeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide") {
            excludeButton.image = image
            excludeButton.imagePosition = .imageOnly
        } else {
            excludeButton.title = "Hide"
            excludeButton.font = .systemFont(ofSize: 11, weight: .medium)
        }

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        addSubview(iconView)
        addSubview(textStack)
        addSubview(excludeButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: excludeButton.leadingAnchor, constant: -12),

            excludeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            excludeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            excludeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            excludeButton.heightAnchor.constraint(equalToConstant: 26)
        ])

        updateColors()
    }

    @objc private func excludeClicked() {
        onExclude?()
    }

    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        titleLabel.textColor = selected ? .selectedTextColor : .labelColor
        subtitleLabel.textColor = selected ? .selectedTextColor : .secondaryLabelColor
        excludeButton.contentTintColor = selected ? .selectedTextColor : .secondaryLabelColor
    }
}

private final class LauncherWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let panel: FloatingPanel
    private let searchField = LauncherSearchField()
    private let indexingIndicator = NSProgressIndicator()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let indexer = ApplicationIndexer()
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let openSettingsAction: () -> Void

    private var allItems: [LaunchItem] = []
    private var filteredItems: [LaunchItem] = []
    private var isIndexing = false
    private var needsReindexAfterCurrent = false

    init(
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        openSettingsAction: @escaping () -> Void
    ) {
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
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
        reindex()
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        searchField.stringValue = ""
        applyFilter()
        searchField.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in
            self?.reindex()
        }
    }

    func hide() {
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
        setIndexing(true)
        updateEmptyState(query: searchField.stringValue)

        let includedPaths = inclusionStore.includedPaths
        DispatchQueue.global(qos: .userInitiated).async { [indexer] in
            let items = indexer.load(includedPaths: includedPaths)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.allItems = items
                self.isIndexing = false

                if self.needsReindexAfterCurrent {
                    self.reindex()
                    self.applyFilter()
                } else {
                    self.setIndexing(false)
                    self.applyFilter()
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
        panel.commandHandler = { [weak self] command in
            self?.handle(command: command) ?? false
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

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.placeholderString = "Search /Applications"
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

        rootView.addSubview(searchField)
        rootView.addSubview(indexingIndicator)
        rootView.addSubview(scrollView)
        rootView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: indexingIndicator.leadingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 42),

            indexingIndicator.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            indexingIndicator.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            indexingIndicator.widthAnchor.constraint(equalToConstant: 18),
            indexingIndicator.heightAnchor.constraint(equalToConstant: 18),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
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

    private func selectFirstResult() {
        guard !filteredItems.isEmpty else {
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
        case .open:
            openSelected()
        case .close:
            hide()
        case .reindex:
            reindex()
        case .settings:
            openSettingsAction()
        }
        return true
    }

    private func moveSelection(by delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = max(0, min(filteredItems.count - 1, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func openSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return }
        let item = filteredItems[row]
        hide()
        launch(item)
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

    func refreshAfterExclusionsChanged() {
        applyFilter()
    }

    func refreshAfterInclusionsChanged() {
        reindex()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        54
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCellView.reuseIdentifier, owner: self) as? ResultCellView
            ?? ResultCellView(frame: .zero)
        let item = filteredItems[row]
        cell.configure(with: item) { [weak self] in
            self?.exclude(item)
        }
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(preservePreviousOnEmpty: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            return handle(command: .up)
        case #selector(NSResponder.moveDown(_:)):
            return handle(command: .down)
        case #selector(NSResponder.insertNewline(_:)):
            return handle(command: .open)
        case #selector(NSResponder.cancelOperation(_:)):
            return handle(command: .close)
        default:
            return false
        }
    }
}

private enum LaunchAtStartupController {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

private final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
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

private final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openAction: () -> Void
    private let reindexAction: () -> Void
    private let settingsAction: () -> Void

    init(
        openAction: @escaping () -> Void,
        reindexAction: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) {
        self.openAction = openAction
        self.reindexAction = reindexAction
        self.settingsAction = settingsAction
        super.init()
        buildMenu()
    }

    private func buildMenu() {
        if let button = statusItem.button {
            button.image = nil
            button.title = "🦾"
            button.font = .systemFont(ofSize: 16)
            button.toolTip = "Bucky"
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Bucky", action: #selector(open), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let reindexItem = NSMenuItem(title: "Reindex Applications", action: #selector(reindex), keyEquivalent: "")
        reindexItem.target = self
        menu.addItem(reindexItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Bucky", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func open() {
        openAction()
    }

    @objc private func reindex() {
        reindexAction()
    }

    @objc private func settings() {
        settingsAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    let configuration: HotKeyConfiguration
    private let onHotKey: () -> Void

    init(configuration: HotKeyConfiguration, onHotKey: @escaping () -> Void) throws {
        self.configuration = configuration
        self.onHotKey = onHotKey
        try install()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func install() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.onHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.installHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: "Bcky".fourCharCode, id: 1)
        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            throw HotKeyError.register(registrationStatus)
        }
    }
}

private enum HotKeyError: LocalizedError {
    case installHandler(OSStatus)
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return "Could not install hotkey handler. OSStatus \(status)."
        case .register(let status):
            return "Could not register Option+Space. OSStatus \(status)."
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let inclusionStore = InclusionStore()
    private let exclusionStore = ExclusionStore()
    private var launcherController: LauncherWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var statusMenuController: StatusMenuController?
    private var hotKeyController: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let launcherController = LauncherWindowController(
            inclusionStore: inclusionStore,
            exclusionStore: exclusionStore,
            openSettingsAction: { [weak self] in self?.showSettings() }
        )
        self.launcherController = launcherController

        statusMenuController = StatusMenuController(
            openAction: { [weak launcherController] in launcherController?.show() },
            reindexAction: { [weak launcherController] in launcherController?.reindex() },
            settingsAction: { [weak self] in self?.showSettings() }
        )

        _ = registerHotKey(settingsStore.settings.hotKey)
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                inclusionStore: inclusionStore,
                exclusionStore: exclusionStore,
                hotKeyChangeHandler: { [weak self] hotKey in
                    self?.registerHotKey(hotKey) ?? false
                },
                inclusionsChangedHandler: { [weak self] in
                    self?.launcherController?.refreshAfterInclusionsChanged()
                },
                exclusionsChangedHandler: { [weak self] in
                    self?.launcherController?.refreshAfterExclusionsChanged()
                }
            )
        }

        settingsWindowController?.show()
    }

    private func registerHotKey(_ hotKey: HotKeyConfiguration) -> Bool {
        if hotKeyController?.configuration == hotKey {
            return true
        }

        do {
            let controller = try HotKeyController(configuration: hotKey) { [weak self] in
                self?.launcherController?.toggle()
            }
            hotKeyController = controller
            return true
        } catch {
            showHotKeyAlert(error, hotKey: hotKey)
            return false
        }
    }

    private func showHotKeyAlert(_ error: Error, hotKey: HotKeyConfiguration) {
        let alert = NSAlert()
        alert.messageText = "Bucky could not register \(hotKey.displayName)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private func normalized(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0

    if deviceFlags.contains(.control) {
        modifiers |= UInt32(controlKey)
    }
    if deviceFlags.contains(.option) {
        modifiers |= UInt32(optionKey)
    }
    if deviceFlags.contains(.shift) {
        modifiers |= UInt32(shiftKey)
    }
    if deviceFlags.contains(.command) {
        modifiers |= UInt32(cmdKey)
    }

    return modifiers
}

private func carbonModifierDisplayNames(_ modifiers: UInt32) -> [String] {
    var names: [String] = []

    if modifiers & UInt32(controlKey) != 0 {
        names.append("Control")
    }
    if modifiers & UInt32(optionKey) != 0 {
        names.append("Option")
    }
    if modifiers & UInt32(shiftKey) != 0 {
        names.append("Shift")
    }
    if modifiers & UInt32(cmdKey) != 0 {
        names.append("Command")
    }

    return names
}

private func displayKeyName(for keyCode: UInt32, characters: String?) -> String {
    switch Int(keyCode) {
    case kVK_Space:
        return "Space"
    case kVK_Return:
        return "Return"
    case kVK_Tab:
        return "Tab"
    case kVK_Escape:
        return "Escape"
    case kVK_Delete:
        return "Delete"
    case kVK_ForwardDelete:
        return "Forward Delete"
    case kVK_LeftArrow:
        return "Left"
    case kVK_RightArrow:
        return "Right"
    case kVK_UpArrow:
        return "Up"
    case kVK_DownArrow:
        return "Down"
    case kVK_Home:
        return "Home"
    case kVK_End:
        return "End"
    case kVK_PageUp:
        return "Page Up"
    case kVK_PageDown:
        return "Page Down"
    default:
        break
    }

    guard let characters, !characters.isEmpty else {
        return "Key \(keyCode)"
    }

    if characters == "," {
        return "Comma"
    }

    let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "Key \(keyCode)"
    }

    return trimmed.uppercased()
}

private extension HotKeyConfiguration {
    init?(event: NSEvent) {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            return nil
        }

        let keyCode = UInt32(event.keyCode)
        self.init(
            keyCode: keyCode,
            modifiers: modifiers,
            keyName: displayKeyName(for: keyCode, characters: event.charactersIgnoringModifiers)
        )
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}

private extension NSEvent {
    var isCommandR: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && charactersIgnoringModifiers?.lowercased() == "r"
    }

    var isCommandComma: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && charactersIgnoringModifiers == ","
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
