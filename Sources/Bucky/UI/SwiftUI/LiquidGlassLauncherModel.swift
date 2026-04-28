import AppKit
import Carbon
import CoreGraphics
import CoreServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
final class LiquidGlassLauncherModel: ObservableObject {
    @Published var mode: LauncherMode = .applications
    @Published var query = ""
    @Published var filteredItems: [LaunchItem] = []
    @Published var toolItems: [ToolItem] = []
    @Published var selectedIndex = 0
    @Published var selectionScrollRequest: SelectionScrollRequest?
    @Published var isIndexing = false
    @Published var isPresented = false
    @Published var isPinned = false {
        didSet { pinnedChangedAction?(isPinned) }
    }

    var hideAction: (() -> Void)?
    var openSettingsAction: (() -> Void)?
    var reindexAction: (() -> Void)?
    var pinnedChangedAction: ((Bool) -> Void)?

    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let calculationHistoryStore: CalculationHistoryStore
    private var allItems: [LaunchItem] = []
    private var needsReindexAfterCurrent = false
    private var pendingCalculationHistoryTimer: Timer?
    private var pendingCalculationHistoryExpression: String?
    private var pendingCalculationHistoryResult: String?
    private var selectionScrollRequestID = 0

    init(
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore
    ) {
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.calculationHistoryStore = calculationHistoryStore
    }

    var placeholder: String {
        switch mode {
        case .applications:
            return "Search for Apps"
        case .tools:
            return "Calculate Numbers and Define Words"
        }
    }

    var resultCount: Int {
        switch mode {
        case .applications:
            return filteredItems.count
        case .tools:
            return toolItems.count
        }
    }

    var canClearHistory: Bool {
        mode == .tools && !calculationHistoryStore.calculations.isEmpty
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
        case .tools:
            if toolItems.isEmpty {
                return inputIsBlank ? "No calculation history" : "No tool results"
            }
        }

        return nil
    }

    var inputIsBlank: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func show(mode: LauncherMode) {
        self.mode = mode
        query = ""
        selectedIndex = 0
        isPinned = false
        applyCurrentMode()
        requestSelectionScroll(anchor: .top, direction: -1)
    }

    func queryDidChange() {
        applyCurrentMode(preservePreviousOnEmpty: true)
    }

    func handle(command: LauncherCommand) -> Bool {
        switch command {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
        case .top:
            moveSelection(to: 0, anchor: .top, direction: -1)
        case .bottom:
            moveSelection(to: resultCount - 1, anchor: .bottom, direction: 1)
        case .open:
            activateSelected()
        case .close:
            clearInputOrHide()
        case .reindex:
            reindex()
        case .settings:
            openSettingsAction?()
        case .toggleToolsMode:
            return toggleToolsModeFromShortcut()
        case .clearHistory:
            clearHistory()
        case .togglePin:
            isPinned.toggle()
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
        guard mode == .applications else { return }
        applyFilter()
    }

    func exclude(_ item: LaunchItem) {
        exclusionStore.exclude(item)
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

    private func applyCurrentMode(preservePreviousOnEmpty: Bool = false) {
        switch mode {
        case .applications:
            cancelPendingCalculationHistory()
            applyFilter(preservePreviousOnEmpty: preservePreviousOnEmpty)
        case .tools:
            calculationHistoryStore.load()
            applyToolsResults()
        }
    }

    private func applyFilter(preservePreviousOnEmpty: Bool = false) {
        let visibleItems = allItems.filter { !exclusionStore.isExcluded($0) }
        let nextItems = Self.filter(visibleItems, query: query)

        if preservePreviousOnEmpty,
           nextItems.isEmpty,
           !filteredItems.isEmpty,
           !inputIsBlank {
            return
        }

        filteredItems = nextItems
        clampSelection()
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

    private func applyToolsResults(scheduleHistory: Bool = true) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelPendingCalculationHistory()

        if trimmedQuery.isEmpty {
            toolItems = calculationHistoryItems()
        } else if ArithmeticEvaluator.isArithmeticInput(trimmedQuery) {
            if let result = ArithmeticEvaluator.evaluate(trimmedQuery) {
                toolItems = [
                    ToolItem(
                        title: result,
                        subtitle: "\(trimmedQuery) =",
                        copyText: result,
                        kind: .calculation
                    )
                ] + calculationHistoryItems(excludingExpression: trimmedQuery, result: result)

                if scheduleHistory, ArithmeticEvaluator.shouldStoreInHistory(trimmedQuery) {
                    scheduleCalculationHistory(expression: trimmedQuery, result: result)
                }
            } else {
                toolItems = [
                    ToolItem(
                        title: "Complete the calculation",
                        subtitle: trimmedQuery,
                        copyText: nil,
                        kind: .message
                    )
                ] + calculationHistoryItems()
            }
        } else {
            let dictionaryResults = DictionaryLookup.results(for: trimmedQuery)
            if dictionaryResults.isEmpty {
                toolItems = [
                    ToolItem(
                        title: "No dictionary matches",
                        subtitle: trimmedQuery,
                        copyText: nil,
                        kind: .message
                    )
                ]
            } else {
                toolItems = dictionaryResults.map { result in
                    ToolItem(
                        title: result.term,
                        subtitle: singleLine(result.definition),
                        copyText: nil,
                        kind: .dictionary
                    )
                }
            }
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

        if refreshResults, mode == .tools {
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
        applyCurrentMode()
    }

    private func toggleToolsModeFromShortcut() -> Bool {
        if isPinned {
            return true
        }
        guard inputIsBlank else { return false }

        switch mode {
        case .applications:
            mode = .tools
        case .tools:
            mode = .applications
        }
        query = ""
        applyCurrentMode()

        if mode == .applications {
            reindexAction?()
        }

        return true
    }

    private func moveSelection(by delta: Int) {
        guard resultCount > 0 else { return }
        let nextIndex = max(0, min(resultCount - 1, selectedIndex + delta))
        selectedIndex = nextIndex
        requestSelectionScroll(anchor: .nearest, direction: delta)
    }

    private func moveSelection(to index: Int, anchor: SelectionScrollAnchor, direction: Int) {
        guard resultCount > 0 else { return }
        selectedIndex = max(0, min(resultCount - 1, index))
        requestSelectionScroll(anchor: anchor, direction: direction)
    }

    private func clampSelection() {
        guard resultCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = max(0, min(resultCount - 1, selectedIndex))
    }

    private func requestSelectionScroll(anchor: SelectionScrollAnchor, direction: Int) {
        guard resultCount > 0 else { return }
        selectionScrollRequestID += 1
        selectionScrollRequest = SelectionScrollRequest(
            id: selectionScrollRequestID,
            index: selectedIndex,
            direction: direction,
            anchor: anchor
        )
    }

    private func activateSelected() {
        switch mode {
        case .applications:
            guard selectedIndex >= 0, selectedIndex < filteredItems.count else { return }
            let item = filteredItems[selectedIndex]
            hideAction?()
            launch(item)
        case .tools:
            guard selectedIndex >= 0, selectedIndex < toolItems.count else { return }
            activate(toolItems[selectedIndex])
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
    let direction: Int
    let anchor: SelectionScrollAnchor
}
