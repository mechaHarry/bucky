import AppKit
import SwiftUI

@available(macOS 26.0, *)
@MainActor
final class LiquidGlassLauncherModel: ObservableObject {
    @Published var mode: LauncherMode = .applications
    @Published var query = ""
    @Published var filteredItemIDs: [AppRowID] = []
    @Published var toolItems: [ToolItem] = []
    @Published private var activatedFileBrowserModel: FileBrowserModel?
    @Published var selectedIndex = 0
    @Published var selectionScrollRequest: SelectionScrollRequest?
    @Published var isIndexing = false
    @Published var animationTiming: LauncherAnimationTiming
    @Published var isPresented = false
    @Published var isWindowKey = false
    @Published var isShowingSettings = false
    @Published var isShowingHelp = false
    @Published var isPinned = false {
        didSet { pinnedChangedAction?(isPinned) }
    }

    var hideAction: (() -> Void)?
    var openSettingsAction: (() -> Void)?
    var openHelpAction: (() -> Void)?
    var returnToLauncherAction: (() -> Void)?
    var reindexAction: (() -> Void)?
    var pinnedChangedAction: ((Bool) -> Void)?
    var modeWillSwitchAction: ((LauncherMode, LauncherMode) -> Void)?

    private let settingsStore: SettingsStore
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let calculationHistoryStore: CalculationHistoryStore
    private let dictionaryHistoryStore: DictionaryHistoryStore
    private let stoneProviders: StoneProviderRegistry
    private let fileBrowserModelFactory: () -> FileBrowserModel
    private let applicationIndexSnapshotCache: ApplicationIndexSnapshotCache
    private var appRowStore = ApplicationRowStore()
    private var indexedItems: [LaunchItem] = []
    private var filterCache = ApplicationFilterCache()
    private var applicationQuery = ""
    private var calculatorQuery = ""
    private var textStoneQueries: [StoneID: String] = [:]
    private var textStoneResultSnapshots: [StoneID: StoneResultSnapshot] = [:]
    private var needsReindexAfterCurrent = false
    private var pendingCalculationHistoryTimer: Timer?
    private var pendingCalculationHistoryExpression: String?
    private var pendingCalculationHistoryResult: String?
    private var pendingApplicationFilterTask: Task<Void, Never>?
    private var applicationFilterRequestGate = StoneResultRequestGate()
    private var pendingTextStoneUpdateTasks: [StoneID: Task<Void, Never>] = [:]
    private var textStoneRequestGates: [StoneID: StoneResultRequestGate] = [:]
    private var pendingModeSnapshotTask: Task<Void, Never>?
    private var modeSnapshotGeneration = 0
    private var warmCacheTask: Task<Void, Never>?
    private var selectionScrollRequestID = 0

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        dictionaryHistoryStore: DictionaryHistoryStore = DictionaryHistoryStore(),
        dictionaryLookup: @escaping @Sendable (String) -> [DictionaryResult] = { DictionaryLookup.results(for: $0) },
        dictionaryOpenHandler: @escaping @MainActor (String) -> Void = LiquidGlassLauncherModel.openDictionaryTerm,
        textStoneProviders: [any StoneProvider] = [],
        stoneProviders: [any StoneProvider] = [],
        fileBrowserModel: FileBrowserModel? = nil,
        fileBrowserModelFactory: (() -> FileBrowserModel)? = nil,
        applicationIndexSnapshotCache: ApplicationIndexSnapshotCache = ApplicationIndexSnapshotCache()
    ) {
        self.settingsStore = settingsStore
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.calculationHistoryStore = calculationHistoryStore
        self.dictionaryHistoryStore = dictionaryHistoryStore
        let dictionaryStone = DictionaryStone(
            historyStore: dictionaryHistoryStore,
            lookup: dictionaryLookup,
            openHandler: dictionaryOpenHandler
        )
        self.stoneProviders = StoneProviderRegistry(
            providers: [dictionaryStone] + textStoneProviders + stoneProviders
        )
        self.applicationIndexSnapshotCache = applicationIndexSnapshotCache
        self.activatedFileBrowserModel = fileBrowserModel
        self.fileBrowserModelFactory = fileBrowserModelFactory ?? {
            MainActor.assumeIsolated {
                FileBrowserModel(startDirectory: settingsStore.settings.fileBrowserStartDirectory)
            }
        }
        animationTiming = settingsStore.settings.animationTiming
        loadCachedApplicationSnapshot()
    }

    deinit {
        pendingApplicationFilterTask?.cancel()
        for task in pendingTextStoneUpdateTasks.values {
            task.cancel()
        }
        pendingModeSnapshotTask?.cancel()
        warmCacheTask?.cancel()
    }

    var fileBrowserModel: FileBrowserModel {
        activateFileBrowserModel()
    }

    var filteredItems: [LaunchItem] {
        appRowStore.items(for: filteredItemIDs)
    }

    var filteredIconURLs: [URL] {
        filteredItemIDs.compactMap { appRowStore.item(for: $0)?.url }
    }

    func item(for id: AppRowID) -> LaunchItem? {
        appRowStore.item(for: id)
    }

    var activeFileBrowserModel: FileBrowserModel? {
        activatedFileBrowserModel
    }

    var availableModes: [LauncherMode] {
        stoneProviders.availableModes
    }

    func mode(forCommandNumber commandNumber: Int) -> LauncherMode? {
        stoneProviders.mode(forShortcutNumber: commandNumber)
    }

    var placeholder: String {
        mode.placeholder
    }

    var resultCount: Int {
        if mode.stoneDefinition.surface.usesFileBrowser {
            return MainActor.assumeIsolated {
                fileBrowserModel.entries.count
            }
        }

        return resultSnapshot.rows.count
    }

    var canClearHistory: Bool {
        mode == .calculator && !calculationHistoryStore.calculations.isEmpty
    }

    var emptyMessage: String? {
        guard !mode.stoneDefinition.surface.usesFileBrowser else {
            if MainActor.assumeIsolated({ fileBrowserModel.entries.isEmpty }) {
                return "No files"
            }
            return nil
        }

        return resultSnapshot.surfaceMessage
    }

    var resultSnapshot: StoneResultSnapshot {
        if let snapshot = textStoneResultSnapshots[mode.stoneID] {
            return snapshot
        }

        if mode == .applications {
            if filteredItemIDs.isEmpty {
                if isIndexing && appRowStore.isEmpty {
                    return .loading(message: "Loading apps")
                }
                return .empty(message: inputIsBlank ? "No launchable items found" : "No matches")
            }
            return .loaded(rows: filteredItemIDs.compactMap { id in
                guard let item = appRowStore.item(for: id) else { return nil }
                return StoneResultRow.application(id: id, item: item)
            })
        }

        if mode == .calculator {
            if toolItems.isEmpty {
                return .empty(message: inputIsBlank ? "No calculation history" : "No tool results")
            }
            return toolResultSnapshot()
        }

        if mode.stoneDefinition.surface.usesFileBrowser {
            return .loaded(rows: MainActor.assumeIsolated { fileBrowserModel.entries.map(StoneResultRow.file) })
        }

        return .loaded(rows: [])
    }

    func resultRow(at index: Int) -> StoneResultRow? {
        let rows = resultSnapshot.rows
        guard index >= 0, index < rows.count else { return nil }
        return rows[index]
    }

    var inputIsBlank: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func show(mode: LauncherMode) {
        isShowingSettings = false
        isShowingHelp = false
        applicationQuery = ""
        calculatorQuery = ""
        textStoneQueries.removeAll()
        self.mode = mode
        query = storedQuery(for: mode)
        selectedIndex = 0
        isPinned = false
        applyCurrentMode()
        requestSelectionScroll(anchor: .top)
    }

    func showSettings() {
        isShowingSettings = true
        isShowingHelp = false
        isPinned = false
    }

    func hideSettings() {
        isShowingSettings = false
    }

    func showHelp() {
        isShowingSettings = false
        isShowingHelp = true
        isPinned = false
    }

    func hideHelp() {
        isShowingHelp = false
    }

    func showLauncherSurface() {
        isShowingSettings = false
        isShowingHelp = false
    }

    func resetPanelVisibilityAfterHide() {
        isShowingSettings = false
        isShowingHelp = false
    }

    func setWindowKeyState(_ isWindowKey: Bool) {
        guard self.isWindowKey != isWindowKey else { return }
        self.isWindowKey = isWindowKey
    }

    func prepareFileBrowserMode() {
        guard mode.stoneDefinition.surface.usesFileBrowser else { return }
        let model = activateFileBrowserModel()
        selectedIndex = MainActor.assumeIsolated {
            model.selectedIndex
        }
    }

    func queryDidChange() {
        storeCurrentQuery()
        applyCurrentMode(preservePreviousOnEmpty: true)
    }

    func insertTextInput(_ character: Character) {
        query.append(character)
        queryDidChange()
    }

    func handle(command: LauncherCommand) -> Bool {
        switch command {
        case .up:
            if mode.stoneDefinition.surface.usesFileBrowser {
                return handleFileBrowserCommand(command)
            }
            moveSelection(by: -1)
        case .down:
            if mode.stoneDefinition.surface.usesFileBrowser {
                return handleFileBrowserCommand(command)
            }
            moveSelection(by: 1)
        case .top:
            if mode.stoneDefinition.surface.usesFileBrowser {
                return handleFileBrowserCommand(command, anchor: .top)
            }
            moveSelection(to: 0, anchor: .top)
        case .bottom:
            if mode.stoneDefinition.surface.usesFileBrowser {
                return handleFileBrowserCommand(command, anchor: .bottom)
            }
            moveSelection(to: resultCount - 1, anchor: .bottom)
        case .open:
            if mode.stoneDefinition.surface.usesFileBrowser {
                return handleFileBrowserCommand(command)
            }
            activateSelected()
        case .close:
            if mode.stoneDefinition.surface.usesFileBrowser, fileBrowserFocusState != .browse {
                return handleFileBrowserCommand(command)
            }
            clearInputOrHide()
        case .reindex:
            reindex()
        case .settings:
            openSettingsAction?()
        case .help:
            openHelpAction?()
        case let .switchMode(nextMode):
            return switchMode(nextMode)
        case .previousMode:
            return switchMode(adjacentAvailableMode(offset: -1))
        case .nextMode:
            return switchMode(adjacentAvailableMode(offset: 1))
        case .clearHistory:
            clearHistory()
        case .togglePin:
            if mode.stoneDefinition.surface.usesFileBrowser {
                return handleFileBrowserCommand(command)
            }
            isPinned.toggle()
        case .left, .right, .prepareSpaceInteraction, .space, .shiftSpace, .beginSpaceHold, .endSpaceHold,
                .alphaNumeric, .shiftAlphaNumeric, .beginPinnedFocus, .endPinnedFocus, .historyBack, .historyForward:
            guard mode.stoneDefinition.surface.usesFileBrowser else { return false }
            return handleFileBrowserCommand(command)
        }

        return true
    }

    func reindex() {
        cancelPendingApplicationFilter()
        cancelPendingTextStoneUpdates()
        guard !isIndexing else {
            needsReindexAfterCurrent = true
            return
        }

        isIndexing = true
        needsReindexAfterCurrent = false
        inclusionStore.load()
        exclusionStore.load()

        let includedPaths = inclusionStore.includedPaths
        let applicationIndexSnapshotCache = applicationIndexSnapshotCache
        DispatchQueue.global(qos: .userInitiated).async { [applicationIndexSnapshotCache] in
            let items = ApplicationIndexer().load(includedPaths: includedPaths)
            applicationIndexSnapshotCache.save(items)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.publishApplicationSnapshot(items)
                self.isIndexing = false

                if self.needsReindexAfterCurrent {
                    self.reindex()
                } else if self.mode == .applications {
                    self.applyFilter()
                }
                self.warmCurrentCaches()
            }
        }
    }

    private func loadCachedApplicationSnapshot() {
        DispatchQueue.global(qos: .utility).async { [applicationIndexSnapshotCache] in
            let items = applicationIndexSnapshotCache.load()
            guard !items.isEmpty else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.indexedItems.isEmpty else { return }
                self.publishApplicationSnapshot(items)
                if self.mode == .applications {
                    self.applyFilter()
                }
            }
        }
    }

    private func publishApplicationSnapshot(_ items: [LaunchItem]) {
        let previousItems = indexedItems
        indexedItems = items
        if previousItems != items {
            if appRowStore.replaceAllIfChanged(items) {
                rebuildVisibleItems()
            }
        }
    }

    func startBackgroundWarmCaches() {
        guard warmCacheTask == nil else { return }

        warmCacheTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let snapshot = await MainActor.run { [weak self] in
                    self?.applicationWarmCacheSnapshot()
                }

                guard let snapshot else {
                    await MainActor.run { [weak self] in
                        self?.warmNonApplicationCaches()
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }

                do {
                    let entries = await Task.detached(priority: .utility) {
                        Self.warmFilterEntries(
                            rowStore: snapshot.rowStore,
                            ids: snapshot.ids,
                            normalizedQuery: snapshot.normalizedQuery
                        )
                    }.value

                    await MainActor.run { [weak self] in
                        self?.storeWarmFilterEntries(entries, generation: snapshot.generation)
                        self?.warmNonApplicationCaches()
                    }
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
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
        reindex()
    }

    func exclude(_ item: LaunchItem) {
        cancelPendingApplicationFilter()
        exclusionStore.exclude(item)
        rebuildVisibleItems()
        applyFilter()
    }

    func exclude(_ row: StoneResultRow) {
        guard case let .application(id) = row.id,
              let item = appRowStore.item(for: id) else {
            return
        }

        exclude(item)
    }

    func clearHistory() {
        cancelPendingTextStoneUpdates()
        calculationHistoryStore.clear()
        applyToolsResults(scheduleHistory: false)
    }

    func activate(_ row: StoneResultRow) {
        let activation = stoneProviders.activation(for: mode.stoneID, row: row) ?? row.primaryActivation
        perform(activation, for: row)
    }

    func performAccessoryActivation(for row: StoneResultRow) {
        perform(row.accessoryActivation, for: row)
    }

    func cancelPendingCalculationHistory() {
        pendingCalculationHistoryTimer?.invalidate()
        pendingCalculationHistoryTimer = nil
        pendingCalculationHistoryExpression = nil
        pendingCalculationHistoryResult = nil
    }

    private func cancelPendingTextStoneUpdates() {
        for stoneID in stoneProviders.registeredStoneIDs {
            cancelPendingTextStoneUpdate(for: stoneID)
        }
    }

    private func cancelPendingTextStoneUpdate(for stoneID: StoneID) {
        var requestGate = textStoneRequestGates[stoneID] ?? StoneResultRequestGate()
        requestGate.cancel()
        textStoneRequestGates[stoneID] = requestGate
        stoneProviders.cancel(for: stoneID)
        pendingTextStoneUpdateTasks[stoneID]?.cancel()
        pendingTextStoneUpdateTasks[stoneID] = nil
    }

    private func beginTextStoneRequest(for stoneID: StoneID, query: String) -> StoneResultRequestGate.Token {
        var requestGate = textStoneRequestGates[stoneID] ?? StoneResultRequestGate()
        let token = requestGate.begin(query: query)
        textStoneRequestGates[stoneID] = requestGate
        return token
    }

    private func acceptsTextStoneRequest(
        _ token: StoneResultRequestGate.Token,
        for stoneID: StoneID,
        query: String
    ) -> Bool {
        textStoneRequestGates[stoneID]?.accepts(token, currentQuery: query) == true
    }

    private func cancelPendingApplicationFilter() {
        applicationFilterRequestGate.cancel()
        pendingApplicationFilterTask?.cancel()
        pendingApplicationFilterTask = nil
    }

    private func cancelPendingModeSnapshot() {
        modeSnapshotGeneration += 1
        pendingModeSnapshotTask?.cancel()
        pendingModeSnapshotTask = nil
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
        if stoneProviders.provider(for: mode.stoneID) != nil {
            applyToolsResults()
            return
        }

        switch mode {
        case .applications:
            cancelPendingCalculationHistory()
            cancelPendingTextStoneUpdates()
            if appRowStore.visibleIDs.isEmpty, !appRowStore.isEmpty {
                rebuildVisibleItems()
            }
            applyApplicationFilter(preservePreviousOnEmpty: preservePreviousOnEmpty)
        case .calculator:
            applyToolsResults()
        case .files:
            cancelPendingCalculationHistory()
            cancelPendingTextStoneUpdates()
            toolItems = []
            selectedIndex = MainActor.assumeIsolated {
                fileBrowserModel.selectedIndex
            }
        default:
            return
        }
    }

    private func applyFilter(preservePreviousOnEmpty: Bool = false) {
        let cacheKey = normalized(query)
        let nextIDs = filterCache.results(for: cacheKey, generation: appRowStore.generation) {
            Self.filterIDs(appRowStore.visibleIDs, rowStore: appRowStore, normalizedQuery: cacheKey)
        }

        if preservePreviousOnEmpty,
           nextIDs.isEmpty,
           !filteredItemIDs.isEmpty,
           !inputIsBlank {
            return
        }

        filteredItemIDs = nextIDs
        prewarmFilterCache(for: cacheKey)
        clampSelection()
    }

    private func applyApplicationFilter(preservePreviousOnEmpty: Bool = false) {
        let cacheKey = normalized(query)
        switch ToolResultsSnapshotPolicy.update(for: .applications, query: query) {
        case .immediate:
            cancelPendingApplicationFilter()
            applyFilter(preservePreviousOnEmpty: preservePreviousOnEmpty)
        case let .deferred(delayNanoseconds):
            applyDeferredApplicationFilter(
                for: cacheKey,
                delayNanoseconds: delayNanoseconds,
                preservePreviousOnEmpty: preservePreviousOnEmpty
            )
        }
    }

    private func applyDeferredApplicationFilter(
        for cacheKey: String,
        delayNanoseconds: UInt64,
        preservePreviousOnEmpty: Bool
    ) {
        let token = applicationFilterRequestGate.begin(query: cacheKey)
        let rowStore = appRowStore
        let ids = appRowStore.visibleIDs
        pendingApplicationFilterTask?.cancel()
        pendingApplicationFilterTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            let nextItems = await Task.detached(priority: .userInitiated) {
                Self.filterIDs(ids, rowStore: rowStore, normalizedQuery: cacheKey)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self,
                      self.mode == .applications,
                      self.applicationFilterRequestGate.accepts(token, currentQuery: normalized(self.query)) else {
                    return
                }

                self.pendingApplicationFilterTask = nil
                self.filterCache.store(nextItems, for: cacheKey)
                if preservePreviousOnEmpty,
                   nextItems.isEmpty,
                   !self.filteredItemIDs.isEmpty,
                   !self.inputIsBlank {
                    return
                }

                self.filteredItemIDs = nextItems
                self.prewarmFilterCache(for: cacheKey)
                self.clampSelection()
            }
        }
    }

    private func rebuildVisibleItems() {
        appRowStore.rebuildVisibleIDs { !exclusionStore.isExcluded($0) }
        filterCache.removeAll()
    }

    private func prewarmFilterCache(for normalizedQuery: String) {
        guard !normalizedQuery.isEmpty else { return }

        filterCache.prewarmDeletionPath(for: normalizedQuery, generation: appRowStore.generation) { prefix in
            Self.filterIDs(appRowStore.visibleIDs, rowStore: appRowStore, normalizedQuery: prefix)
        }
    }

    private func warmCurrentCaches() {
        warmNonApplicationCaches()
    }

    private func warmNonApplicationCaches() {
        _ = calculationHistoryItems()
        _ = dictionaryHistoryStore.words
        _ = activateFileBrowserModel()
    }

    private func applicationWarmCacheSnapshot() -> (
        rowStore: ApplicationRowStore,
        ids: [AppRowID],
        normalizedQuery: String,
        generation: Int
    )? {
        guard !appRowStore.visibleIDs.isEmpty else { return nil }
        return (appRowStore, appRowStore.visibleIDs, normalized(query), appRowStore.generation)
    }

    nonisolated private static func warmFilterEntries(
        rowStore: ApplicationRowStore,
        ids: [AppRowID],
        normalizedQuery: String
    ) -> [(query: String, results: [AppRowID])] {
        var entries: [(query: String, results: [AppRowID])] = []
        var prefix = normalizedQuery

        while !prefix.isEmpty {
            entries.append((prefix, filterIDs(ids, rowStore: rowStore, normalizedQuery: prefix)))
            prefix.removeLast()
        }

        entries.append(("", filterIDs(ids, rowStore: rowStore, normalizedQuery: "")))
        return entries
    }

    private func storeWarmFilterEntries(_ entries: [(query: String, results: [AppRowID])], generation: Int) {
        for entry in entries {
            filterCache.store(entry.results, for: entry.query, generation: generation)
        }
    }

    nonisolated static func filterIDs(
        _ ids: [AppRowID],
        rowStore: ApplicationRowStore,
        normalizedQuery: String
    ) -> [AppRowID] {
        ApplicationSearchEngine.filterIDs(ids, rowStore: rowStore, normalizedQuery: normalizedQuery)
    }

    nonisolated static func filter(_ items: [LaunchItem], normalizedQuery: String) -> [LaunchItem] {
        ApplicationSearchEngine.filter(items, normalizedQuery: normalizedQuery)
    }

    private func applyToolsResults(scheduleHistory: Bool = true) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelPendingCalculationHistory()

        if let provider = stoneProviders.provider(for: mode.stoneID) {
            let stoneID = provider.definition.id
            cancelPendingTextStoneUpdate(for: stoneID)
            toolItems = []

            switch ToolResultsSnapshotPolicy.update(for: mode, query: query) {
            case .immediate:
                applyTextStoneSnapshot(provider.snapshot(for: trimmedQuery), for: stoneID)
            case let .deferred(delayNanoseconds):
                applyDeferredTextStoneResults(
                    for: provider,
                    query: trimmedQuery,
                    delayNanoseconds: delayNanoseconds
                )
            }
            return
        }

        switch ToolResultsSnapshotPolicy.update(for: mode, query: query) {
        case .immediate:
            cancelPendingTextStoneUpdates()
            applyToolResultsSnapshot(
                makeToolItems(for: trimmedQuery, scheduleHistory: scheduleHistory),
                selectLiveCalculation: scheduleHistory
            )
        case let .deferred(delayNanoseconds):
            applyDeferredToolResults(
                for: trimmedQuery,
                delayNanoseconds: delayNanoseconds
            )
        }
    }

    private func applyDeferredToolResults(
        for trimmedQuery: String,
        delayNanoseconds: UInt64
    ) {
        guard let provider = stoneProviders.provider(for: mode.stoneID) else { return }
        applyDeferredTextStoneResults(
            for: provider,
            query: trimmedQuery,
            delayNanoseconds: delayNanoseconds
        )
    }

    private func applyDeferredTextStoneResults(
        for provider: any StoneProvider,
        query: String,
        delayNanoseconds: UInt64
    ) {
        let stoneID = provider.definition.id
        let token = beginTextStoneRequest(for: stoneID, query: query)
        applyTextStoneSnapshot(provider.snapshot(for: query), for: stoneID)
        pendingTextStoneUpdateTasks[stoneID] = Task { [weak self, provider] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let snapshot = await provider.updateSnapshot(for: query)

            guard !Task.isCancelled else { return }

            self?.applyTextStoneUpdate(snapshot, for: stoneID, query: query, token: token)
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
        default:
            return []
        }
    }

    private func applyTextStoneUpdate(
        _ snapshot: StoneResultSnapshot,
        for stoneID: StoneID,
        query: String,
        token: StoneResultRequestGate.Token
    ) {
        guard mode.stoneID == stoneID,
              acceptsTextStoneRequest(
                token,
                for: stoneID,
                query: self.query.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return
        }

        pendingTextStoneUpdateTasks[stoneID] = nil
        applyTextStoneSnapshot(snapshot, for: stoneID)
    }

    private func applyTextStoneSnapshot(_ snapshot: StoneResultSnapshot, for stoneID: StoneID) {
        textStoneResultSnapshots[stoneID] = snapshot
        clampSelection()
    }

    private func applyToolResultsSnapshot(_ nextItems: [ToolItem], selectLiveCalculation: Bool) {
        toolItems = nextItems
        if selectLiveCalculation, mode == .calculator, toolItems.first?.kind == .calculation {
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
        cancelPendingTextStoneUpdates()
        applyCurrentMode()
    }

    private func storeCurrentQuery() {
        if stoneProviders.provider(for: mode.stoneID) != nil {
            textStoneQueries[mode.stoneID] = query
            return
        }

        switch mode {
        case .applications:
            applicationQuery = query
        case .calculator:
            calculatorQuery = query
        case .files:
            break
        default:
            return
        }
    }

    private func storedQuery(for mode: LauncherMode) -> String {
        if stoneProviders.provider(for: mode.stoneID) != nil {
            return textStoneQueries[mode.stoneID] ?? ""
        }

        switch mode {
        case .applications:
            return applicationQuery
        case .calculator:
            return calculatorQuery
        case .files:
            return ""
        default:
            return ""
        }
    }

    private func switchMode(_ nextMode: LauncherMode) -> Bool {
        if mode != nextMode {
            modeWillSwitchAction?(mode, nextMode)
        }
        cancelPendingTextStoneUpdates()
        cancelPendingApplicationFilter()
        storeCurrentQuery()
        mode = nextMode
        query = storedQuery(for: nextMode)
        selectedIndex = 0
        publishLightweightModeSnapshot(for: nextMode)
        scheduleModeSnapshot(for: nextMode)
        return true
    }

    private func adjacentAvailableMode(offset: Int) -> LauncherMode {
        guard let index = availableModes.firstIndex(of: mode) else { return mode }
        let nextIndex = (index + offset + availableModes.count) % availableModes.count
        return availableModes[nextIndex]
    }

    private func publishLightweightModeSnapshot(for mode: LauncherMode) {
        if stoneProviders.provider(for: mode.stoneID) != nil {
            textStoneResultSnapshots[mode.stoneID] = .loaded(rows: [])
            return
        }

        switch mode {
        case .applications:
            break
        case .calculator, .files:
            toolItems = []
        default:
            break
        }
    }

    private func scheduleModeSnapshot(for mode: LauncherMode) {
        cancelPendingModeSnapshot()
        let generation = modeSnapshotGeneration
        pendingModeSnapshotTask = Task { [weak self] in
            await Task.yield()

            await MainActor.run { [weak self] in
                guard let self,
                      self.modeSnapshotGeneration == generation,
                      self.mode == mode else {
                    return
                }

                self.pendingModeSnapshotTask = nil
                self.applyCurrentMode()
                self.requestSelectionScroll(anchor: .top)
            }
        }
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
        if mode.stoneDefinition.surface.usesFileBrowser {
            MainActor.assumeIsolated {
                fileBrowserModel.handle(.open)
            }
            return
        }

        guard let row = resultRow(at: selectedIndex) else { return }
        activate(row)
    }

    private func launch(_ item: LaunchItem) {
        launch(item.launchTarget)
    }

    private func launch(_ target: LaunchTarget) {
        switch target {
        case let .application(url):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    NSLog("Bucky failed to open %@: %@", url.path, error.localizedDescription)
                }
            }
        case let .url(url):
            if !NSWorkspace.shared.open(url) {
                NSLog("Bucky failed to open %@", url.absoluteString)
            }
        case let .shellCommand(command):
            runShellCommand(command)
        }
    }

    private func runShellCommand(_ command: String) {
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            do {
                try process.run()
            } catch {
                NSLog("Bucky failed to run custom action: %@", error.localizedDescription)
            }
        }
    }

    private func perform(_ activation: StoneActivation, for row: StoneResultRow) {
        switch stoneProviders.perform(activation, for: mode.stoneID, row: row) {
        case let .handled(shouldRefresh, resetSelection, shouldHide):
            if shouldRefresh, inputIsBlank {
                applyToolsResults(scheduleHistory: false)
            }
            if resetSelection {
                selectedIndex = 0
                requestSelectionScroll(anchor: .top)
            }
            if shouldHide, !isPinned {
                hideAction?()
            }
            return
        case .unhandled:
            break
        }

        switch activation {
        case let .copy(value):
            if row.kind == .calculation {
                commitPendingCalculationHistory(refreshResults: false)
            }
            copyToPasteboard(value)
        case let .open(target):
            launch(target)
        case .removeHistory:
            return
        case .none:
            return
        }

        if row.kind == .application, !isPinned {
            hideAction?()
        }

        if row.kind != .application, !isPinned {
            hideAction?()
        }
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private static func openDictionaryTerm(_ term: String) {
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

    private func toolResultSnapshot() -> StoneResultSnapshot {
        let rows = toolItems.map(StoneResultRow.tool)
        if rows.count == 1, rows[0].kind == .message {
            return .message(rows[0])
        }

        return .loaded(rows: rows)
    }
}

@available(macOS 26.0, *)
enum SelectionScrollAnchor: Equatable {
    case nearest
    case top
    case bottom
}

@available(macOS 26.0, *)
enum SelectionScrollAnimationPolicy {
    static func shouldAnimate(anchor: SelectionScrollAnchor) -> Bool {
        switch anchor {
        case .nearest:
            return false
        case .top, .bottom:
            return true
        }
    }
}

@available(macOS 26.0, *)
struct SelectionScrollRequest: Equatable {
    let id: Int
    let index: Int
    let anchor: SelectionScrollAnchor
}

@available(macOS 26.0, *)
struct ApplicationFilterCache {
    private var resultsByQuery: [String: [AppRowID]] = [:]
    private var queryOrder: [String] = []
    private var generation: Int?
    private let limit = 96

    mutating func results(for query: String, generation: Int, build: () -> [AppRowID]) -> [AppRowID] {
        resetIfNeeded(generation: generation)
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
        generation: Int,
        build: (String) -> [AppRowID]
    ) {
        resetIfNeeded(generation: generation)
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

    mutating func store(_ results: [AppRowID], for query: String) {
        resultsByQuery[query] = results
        markUsed(query)
        trimIfNeeded()
    }

    mutating func store(_ results: [AppRowID], for query: String, generation: Int) {
        resetIfNeeded(generation: generation)
        store(results, for: query)
    }

    private mutating func markUsed(_ query: String) {
        queryOrder.removeAll { $0 == query }
        queryOrder.append(query)
    }

    private mutating func resetIfNeeded(generation: Int) {
        guard self.generation != generation else { return }
        self.generation = generation
        removeAll()
    }

    private mutating func trimIfNeeded() {
        while queryOrder.count > limit, let oldestQuery = queryOrder.first {
            queryOrder.removeFirst()
            resultsByQuery.removeValue(forKey: oldestQuery)
        }
    }
}
