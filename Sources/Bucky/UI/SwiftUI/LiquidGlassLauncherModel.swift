import AppKit
import SwiftUI

@available(macOS 26.0, *)
final class LiquidGlassLauncherModel: ObservableObject {
    @Published var mode: LauncherMode = .applications
    @Published var query = ""
    @Published var filteredItems: [LaunchItem] = []
    @Published var toolItems: [ToolItem] = []
    @Published private var activatedFileBrowserModel: FileBrowserModel?
    @Published var selectedIndex = 0
    @Published var selectionScrollRequest: SelectionScrollRequest?
    @Published var isIndexing = false
    @Published var animationTiming: LauncherAnimationTiming
    @Published var isPresented = false
    @Published var isWindowKey = true
    @Published var isPinned = false {
        didSet { pinnedChangedAction?(isPinned) }
    }

    var hideAction: (() -> Void)?
    var openSettingsAction: (() -> Void)?
    var reindexAction: (() -> Void)?
    var pinnedChangedAction: ((Bool) -> Void)?
    var modeWillSwitchAction: ((LauncherMode, LauncherMode) -> Void)?

    private let settingsStore: SettingsStore
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let calculationHistoryStore: CalculationHistoryStore
    private let fileBrowserModelFactory: () -> FileBrowserModel
    private var allItems: [LaunchItem] = []
    private var visibleItems: [LaunchItem] = []
    private var filterCache = ApplicationFilterCache()
    private var applicationQuery = ""
    private var calculatorQuery = ""
    private var dictionaryQuery = ""
    private var needsReindexAfterCurrent = false
    private var pendingCalculationHistoryTimer: Timer?
    private var pendingCalculationHistoryExpression: String?
    private var pendingCalculationHistoryResult: String?
    private var selectionScrollRequestID = 0

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        fileBrowserModel: FileBrowserModel? = nil,
        fileBrowserModelFactory: (() -> FileBrowserModel)? = nil
    ) {
        self.settingsStore = settingsStore
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.calculationHistoryStore = calculationHistoryStore
        self.activatedFileBrowserModel = fileBrowserModel
        self.fileBrowserModelFactory = fileBrowserModelFactory ?? {
            MainActor.assumeIsolated {
                FileBrowserModel(startDirectory: settingsStore.settings.fileBrowserStartDirectory)
            }
        }
        animationTiming = settingsStore.settings.animationTiming
    }

    var fileBrowserModel: FileBrowserModel {
        activateFileBrowserModel()
    }

    var placeholder: String {
        mode.placeholder
    }

    var resultCount: Int {
        switch mode {
        case .applications:
            return filteredItems.count
        case .calculator, .dictionary:
            return toolItems.count
        case .files:
            return MainActor.assumeIsolated {
                fileBrowserModel.entries.count
            }
        }
    }

    var canClearHistory: Bool {
        mode == .calculator && !calculationHistoryStore.calculations.isEmpty
    }

    var emptyMessage: String? {
        switch mode {
        case .applications:
            if filteredItems.isEmpty {
                if isIndexing && allItems.isEmpty {
                    return "Loading apps"
                }
                return inputIsBlank ? "No launchable items found" : "No matches"
            }
        case .calculator:
            if toolItems.isEmpty {
                return inputIsBlank ? "No calculation history" : "No tool results"
            }
        case .dictionary:
            if toolItems.isEmpty, !inputIsBlank {
                return "No dictionary matches"
            }
        case .files:
            if MainActor.assumeIsolated({ fileBrowserModel.entries.isEmpty }) {
                return "No files"
            }
        }

        return nil
    }

    var inputIsBlank: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func show(mode: LauncherMode) {
        applicationQuery = ""
        calculatorQuery = ""
        dictionaryQuery = ""
        self.mode = mode
        query = storedQuery(for: mode)
        selectedIndex = 0
        isPinned = false
        applyCurrentMode()
        requestSelectionScroll(anchor: .top)
    }

    func setWindowKeyState(_ isWindowKey: Bool) {
        guard self.isWindowKey != isWindowKey else { return }
        self.isWindowKey = isWindowKey
    }

    func queryDidChange() {
        storeCurrentQuery()
        applyCurrentMode(preservePreviousOnEmpty: true)
    }

    func handle(command: LauncherCommand) -> Bool {
        switch command {
        case .up:
            if mode == .files {
                return handleFileBrowserCommand(command)
            }
            moveSelection(by: -1)
        case .down:
            if mode == .files {
                return handleFileBrowserCommand(command)
            }
            moveSelection(by: 1)
        case .top:
            if mode == .files {
                return handleFileBrowserCommand(command, anchor: .top)
            }
            moveSelection(to: 0, anchor: .top)
        case .bottom:
            if mode == .files {
                return handleFileBrowserCommand(command, anchor: .bottom)
            }
            moveSelection(to: resultCount - 1, anchor: .bottom)
        case .open:
            if mode == .files {
                return handleFileBrowserCommand(command)
            }
            activateSelected()
        case .close:
            if mode == .files, fileBrowserFocusState != .browse {
                return handleFileBrowserCommand(command)
            }
            clearInputOrHide()
        case .reindex:
            reindex()
        case .settings:
            openSettingsAction?()
        case let .switchMode(nextMode):
            return switchMode(nextMode)
        case .clearHistory:
            clearHistory()
        case .togglePin:
            if mode == .files {
                return handleFileBrowserCommand(command)
            }
            isPinned.toggle()
        case .left, .right, .prepareSpaceInteraction, .space, .shiftSpace, .beginSpaceHold, .endSpaceHold,
                .alphaNumeric, .shiftAlphaNumeric, .beginPinnedFocus, .endPinnedFocus, .historyBack, .historyForward:
            guard mode == .files else { return false }
            return handleFileBrowserCommand(command)
        }

        return true
    }

    func reindex() {
        guard !isIndexing else {
            needsReindexAfterCurrent = true
            return
        }

        isIndexing = true
        needsReindexAfterCurrent = false
        inclusionStore.load()
        exclusionStore.load()

        let includedPaths = inclusionStore.includedPaths
        DispatchQueue.global(qos: .userInitiated).async {
            let items = ApplicationIndexer().load(includedPaths: includedPaths)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.allItems = items
                self.rebuildVisibleItems()
                self.isIndexing = false

                if self.needsReindexAfterCurrent {
                    self.reindex()
                } else if self.mode == .applications {
                    self.applyFilter()
                }
            }
        }
    }

    func refreshAfterExclusionsChanged() {
        rebuildVisibleItems()
        guard mode == .applications else { return }
        applyFilter()
    }

    func refreshAfterSettingsChanged() {
        settingsStore.load()
        animationTiming = settingsStore.settings.animationTiming
    }

    func exclude(_ item: LaunchItem) {
        exclusionStore.exclude(item)
        rebuildVisibleItems()
        applyFilter()
    }

    func clearHistory() {
        calculationHistoryStore.clear()
        applyToolsResults(scheduleHistory: false)
    }

    func cancelPendingCalculationHistory() {
        pendingCalculationHistoryTimer?.invalidate()
        pendingCalculationHistoryTimer = nil
        pendingCalculationHistoryExpression = nil
        pendingCalculationHistoryResult = nil
    }

    private func activateFileBrowserModel() -> FileBrowserModel {
        if let activatedFileBrowserModel {
            return activatedFileBrowserModel
        }

        let model = fileBrowserModelFactory()
        activatedFileBrowserModel = model
        return model
    }

    private func applyCurrentMode(preservePreviousOnEmpty: Bool = false) {
        switch mode {
        case .applications:
            cancelPendingCalculationHistory()
            if visibleItems.isEmpty, !allItems.isEmpty {
                rebuildVisibleItems()
            }
            applyFilter(preservePreviousOnEmpty: preservePreviousOnEmpty)
        case .calculator, .dictionary:
            calculationHistoryStore.load()
            applyToolsResults()
        case .files:
            cancelPendingCalculationHistory()
            toolItems = []
            selectedIndex = MainActor.assumeIsolated {
                fileBrowserModel.selectedIndex
            }
        }
    }

    private func applyFilter(preservePreviousOnEmpty: Bool = false) {
        let cacheKey = normalized(query)
        let nextItems = filterCache.results(for: cacheKey) {
            Self.filter(visibleItems, normalizedQuery: cacheKey)
        }

        if preservePreviousOnEmpty,
           nextItems.isEmpty,
           !filteredItems.isEmpty,
           !inputIsBlank {
            return
        }

        filteredItems = nextItems
        prewarmFilterCache(for: cacheKey)
        clampSelection()
    }

    private func rebuildVisibleItems() {
        visibleItems = allItems.filter { !exclusionStore.isExcluded($0) }
        filterCache.removeAll()
    }

    private func prewarmFilterCache(for normalizedQuery: String) {
        guard !normalizedQuery.isEmpty else { return }

        filterCache.prewarmDeletionPath(for: normalizedQuery) { prefix in
            Self.filter(visibleItems, normalizedQuery: prefix)
        }
    }

    static func filter(_ items: [LaunchItem], normalizedQuery: String) -> [LaunchItem] {
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

    private func applyToolsResults(scheduleHistory: Bool = true) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelPendingCalculationHistory()

        switch ToolResultsSnapshotPolicy.update(for: mode, query: query) {
        case .immediate:
            applyToolResultsSnapshot(
                makeToolItems(for: trimmedQuery, scheduleHistory: scheduleHistory)
            )
        }
    }

    private func makeToolItems(for trimmedQuery: String, scheduleHistory: Bool) -> [ToolItem] {
        switch mode {
        case .applications, .files:
            return []
        case .calculator:
            if trimmedQuery.isEmpty {
                return calculationHistoryItems()
            }

            let expression = ArithmeticEvaluator.normalizedExpression(trimmedQuery)
            guard ArithmeticEvaluator.isArithmeticInput(expression) else {
                return [
                    ToolItem(
                        title: "Enter a calculation",
                        subtitle: trimmedQuery,
                        copyText: nil,
                        kind: .message
                    )
                ]
            }

            if let result = ArithmeticEvaluator.evaluate(expression) {
                let items = [
                    ToolItem(
                        title: result,
                        subtitle: "\(expression) =",
                        copyText: result,
                        kind: .calculation
                    )
                ] + calculationHistoryItems(excludingExpression: expression, result: result)

                if scheduleHistory, ArithmeticEvaluator.shouldStoreInHistory(expression) {
                    scheduleCalculationHistory(expression: expression, result: result)
                }
                return items
            } else {
                return [
                    ToolItem(
                        title: "Complete the calculation",
                        subtitle: trimmedQuery,
                        copyText: nil,
                        kind: .message
                    )
                ] + calculationHistoryItems()
            }
        case .dictionary:
            guard !trimmedQuery.isEmpty else {
                return []
            }

            let dictionaryResults = DictionaryLookup.results(for: trimmedQuery)
            if dictionaryResults.isEmpty {
                return [
                    ToolItem(
                        title: "No dictionary matches",
                        subtitle: trimmedQuery,
                        copyText: nil,
                        kind: .message
                    )
                ]
            } else {
                return dictionaryResults.map { result in
                    ToolItem(
                        title: result.term,
                        subtitle: singleLine(result.definition),
                        copyText: nil,
                        kind: .dictionary
                    )
                }
            }
        }
    }

    private func applyToolResultsSnapshot(_ nextItems: [ToolItem]) {
        toolItems = nextItems
        if mode == .calculator, toolItems.first?.kind == .calculation {
            selectedIndex = 0
            requestSelectionScroll(anchor: .top)
            return
        }
        clampSelection()
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
            Task { @MainActor in
                self?.commitPendingCalculationHistory(refreshResults: true)
            }
        }
    }

    private func commitPendingCalculationHistory(refreshResults: Bool) {
        guard let expression = pendingCalculationHistoryExpression,
              let result = pendingCalculationHistoryResult else {
            return
        }

        cancelPendingCalculationHistory()
        calculationHistoryStore.add(expression: expression, result: result)

        if refreshResults, mode == .calculator {
            applyToolsResults(scheduleHistory: false)
        }
    }

    private func clearInputOrHide() {
        if inputIsBlank {
            if isPinned {
                isPinned = false
            }
            hideAction?()
            return
        }

        query = ""
        storeCurrentQuery()
        applyCurrentMode()
    }

    private func storeCurrentQuery() {
        switch mode {
        case .applications:
            applicationQuery = query
        case .calculator:
            calculatorQuery = query
        case .dictionary:
            dictionaryQuery = query
        case .files:
            break
        }
    }

    private func storedQuery(for mode: LauncherMode) -> String {
        switch mode {
        case .applications:
            return applicationQuery
        case .calculator:
            return calculatorQuery
        case .dictionary:
            return dictionaryQuery
        case .files:
            return ""
        }
    }

    private func switchMode(_ nextMode: LauncherMode) -> Bool {
        if mode != nextMode {
            modeWillSwitchAction?(mode, nextMode)
        }
        storeCurrentQuery()
        mode = nextMode
        query = storedQuery(for: nextMode)
        selectedIndex = 0
        applyCurrentMode()
        requestSelectionScroll(anchor: .top)
        if nextMode == .applications {
            reindexAction?()
        }
        return true
    }

    private var fileBrowserFocusState: FileBrowserFocusState {
        MainActor.assumeIsolated {
            fileBrowserModel.focusState
        }
    }

    private func handleFileBrowserCommand(
        _ command: LauncherCommand,
        anchor: SelectionScrollAnchor = .nearest
    ) -> Bool {
        let shouldHideAfterOpenAction = shouldHideAfterFocusedFileOpen(command)
        MainActor.assumeIsolated {
            fileBrowserModel.handle(command)
            selectedIndex = fileBrowserModel.selectedIndex
        }
        if shouldHideAfterOpenAction,
           MainActor.assumeIsolated({ fileBrowserModel.focusState == .browse && fileBrowserModel.statusMessage == nil }) {
            hideAction?()
        }
        requestSelectionScroll(anchor: anchor)
        return true
    }

    private func shouldHideAfterFocusedFileOpen(_ command: LauncherCommand) -> Bool {
        guard case .open = command else { return false }
        return MainActor.assumeIsolated {
            fileBrowserModel.focusState == .previewActions
                && fileBrowserModel.focusableActions.indices.contains(fileBrowserModel.focusedActionIndex)
                && fileBrowserModel.focusableActions[fileBrowserModel.focusedActionIndex] == .open
        }
    }

    private func moveSelection(by delta: Int) {
        guard resultCount > 0 else { return }
        let nextIndex = max(0, min(resultCount - 1, selectedIndex + delta))
        selectedIndex = nextIndex
        requestSelectionScroll(anchor: .nearest)
    }

    private func moveSelection(to index: Int, anchor: SelectionScrollAnchor) {
        guard resultCount > 0 else { return }
        selectedIndex = max(0, min(resultCount - 1, index))
        requestSelectionScroll(anchor: anchor)
    }

    private func clampSelection() {
        guard resultCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = max(0, min(resultCount - 1, selectedIndex))
    }

    private func requestSelectionScroll(anchor: SelectionScrollAnchor) {
        guard resultCount > 0 else { return }
        selectionScrollRequestID += 1
        selectionScrollRequest = SelectionScrollRequest(
            id: selectionScrollRequestID,
            index: selectedIndex,
            anchor: anchor
        )
    }

    private func activateSelected() {
        switch mode {
        case .applications:
            guard selectedIndex >= 0, selectedIndex < filteredItems.count else { return }
            let item = filteredItems[selectedIndex]
            if !isPinned {
                hideAction?()
            }
            launch(item)
        case .calculator, .dictionary:
            guard selectedIndex >= 0, selectedIndex < toolItems.count else { return }
            activate(toolItems[selectedIndex])
        case .files:
            MainActor.assumeIsolated {
                fileBrowserModel.handle(.open)
            }
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

    private func activate(_ item: ToolItem) {
        switch item.kind {
        case .calculation:
            commitPendingCalculationHistory(refreshResults: false)
            copyToPasteboard(item.copyText)
        case .calculationHistory:
            copyToPasteboard(item.copyText)
        case .dictionary:
            openDictionary(term: item.title)
        case .dictionaryHistory:
            return
        case .message:
            return
        }

        if !isPinned {
            hideAction?()
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

    private static let calculationHistoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func singleLine(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

@available(macOS 26.0, *)
enum SelectionScrollAnchor: Equatable {
    case nearest
    case top
    case bottom
}

@available(macOS 26.0, *)
struct SelectionScrollRequest: Equatable {
    let id: Int
    let index: Int
    let anchor: SelectionScrollAnchor
}

@available(macOS 26.0, *)
private struct ApplicationFilterCache {
    private var resultsByQuery: [String: [LaunchItem]] = [:]
    private var queryOrder: [String] = []
    private let limit = 96

    mutating func results(for query: String, build: () -> [LaunchItem]) -> [LaunchItem] {
        if let cachedResults = resultsByQuery[query] {
            markUsed(query)
            return cachedResults
        }

        let results = build()
        store(results, for: query)
        return results
    }

    mutating func prewarmDeletionPath(
        for query: String,
        build: (String) -> [LaunchItem]
    ) {
        var prefix = query

        while !prefix.isEmpty {
            if resultsByQuery[prefix] == nil {
                store(build(prefix), for: prefix)
            } else {
                markUsed(prefix)
            }
            prefix.removeLast()
        }

        if resultsByQuery[""] == nil {
            store(build(""), for: "")
        } else {
            markUsed("")
        }
    }

    mutating func removeAll() {
        resultsByQuery.removeAll(keepingCapacity: true)
        queryOrder.removeAll(keepingCapacity: true)
    }

    private mutating func store(_ results: [LaunchItem], for query: String) {
        resultsByQuery[query] = results
        markUsed(query)
        trimIfNeeded()
    }

    private mutating func markUsed(_ query: String) {
        queryOrder.removeAll { $0 == query }
        queryOrder.append(query)
    }

    private mutating func trimIfNeeded() {
        while queryOrder.count > limit, let oldestQuery = queryOrder.first {
            queryOrder.removeFirst()
            resultsByQuery.removeValue(forKey: oldestQuery)
        }
    }
}
