import AppKit
import SwiftUI

@available(macOS 26.0, *)
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
    @Published var agendaSelectedNoteIndex = 0
    @Published private(set) var agendaNotes: [AgendaNoteReference] = []
    @Published private(set) var openedAgendaNote: AgendaNoteReference?
    @Published var agendaOpenNoteText = ""
    @Published var isAgendaNoteSearchVisible = false
    @Published var isConfirmingAgendaRemoval = false
    @Published private(set) var dictionaryPreview: DictionaryDefinitionPreview?
    @Published private(set) var dictionaryPreviewLoadingTerm: String?
    @Published private(set) var calculatorResultFeedback: CalculatorResultFeedback?
    @Published private(set) var isDictionaryLookupLoading = false
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
    var openAgendaNoteAction: (() -> Void)?

    private let settingsStore: SettingsStore
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let calculationHistoryStore: CalculationHistoryStore
    private let dictionaryHistoryStore: DictionaryHistoryStore
    private let agendaStore: AgendaStore
    private let dictionaryLookup: @Sendable (String) -> [DictionaryResult]
    private let dictionaryOpenHandler: (String) -> Void
    private let pasteboardCopyHandler: (String) -> Void
    private let fileBrowserModelFactory: () -> FileBrowserModel
    private let applicationIndexSnapshotCache: ApplicationIndexSnapshotCache
    private var appRowStore = ApplicationRowStore()
    private var indexedItems: [LaunchItem] = []
    private var filterCache = ApplicationFilterCache()
    private var applicationQuery = ""
    private var dictionaryQuery = ""
    private var agendaQuery = ""
    private var needsReindexAfterCurrent = false
    private var pendingCalculationHistoryTimer: Timer?
    private var pendingCalculationHistoryExpression: String?
    private var pendingCalculationHistoryResult: String?
    private var pendingApplicationFilterTask: Task<Void, Never>?
    private var applicationFilterGeneration = 0
    private var pendingDictionaryLookupTask: Task<Void, Never>?
    private var pendingDictionaryPreviewTask: Task<Void, Never>?
    private var dictionaryPreviewGeneration = 0
    private var dictionaryLookupGeneration = 0
    private var pendingModeSnapshotTask: Task<Void, Never>?
    private var modeSnapshotGeneration = 0
    private var warmCacheTask: Task<Void, Never>?
    private var selectionScrollRequestID = 0
    private var calculatorResultFeedbackID = 0

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        dictionaryHistoryStore: DictionaryHistoryStore = DictionaryHistoryStore(),
        dictionaryLookup: @escaping @Sendable (String) -> [DictionaryResult] = { DictionaryLookup.results(for: $0) },
        dictionaryOpenHandler: @escaping (String) -> Void = LiquidGlassLauncherModel.openDictionaryTerm,
        pasteboardCopyHandler: @escaping (String) -> Void = LiquidGlassLauncherModel.copyStringToPasteboard,
        agendaStore: AgendaStore = AgendaStore(),
        fileBrowserModel: FileBrowserModel? = nil,
        fileBrowserModelFactory: (() -> FileBrowserModel)? = nil,
        applicationIndexSnapshotCache: ApplicationIndexSnapshotCache = ApplicationIndexSnapshotCache()
    ) {
        self.settingsStore = settingsStore
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.calculationHistoryStore = calculationHistoryStore
        self.dictionaryHistoryStore = dictionaryHistoryStore
        self.dictionaryLookup = dictionaryLookup
        self.dictionaryOpenHandler = dictionaryOpenHandler
        self.pasteboardCopyHandler = pasteboardCopyHandler
        self.agendaStore = agendaStore
        self.applicationIndexSnapshotCache = applicationIndexSnapshotCache
        self.activatedFileBrowserModel = fileBrowserModel
        self.fileBrowserModelFactory = fileBrowserModelFactory ?? {
            MainActor.assumeIsolated {
                FileBrowserModel(startDirectory: settingsStore.settings.fileBrowserStartDirectory)
            }
        }
        animationTiming = settingsStore.settings.animationTiming
        syncAgendaSnapshot()
        loadCachedApplicationSnapshot()
    }

    deinit {
        pendingApplicationFilterTask?.cancel()
        pendingDictionaryLookupTask?.cancel()
        pendingDictionaryPreviewTask?.cancel()
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

    var filteredAgendaNotes: [AgendaNoteReference] {
        AgendaFilter.filterNotes(agendaNotes, query: query)
    }

    var isApplicationCalculatorActive: Bool {
        mode == .applications && applicationQueryRoute.calculatorExpression != nil
    }

    var applicationQueryRoute: ApplicationQueryRoute {
        ApplicationQueryRoute(query: query)
    }

    var dictionaryRouteIsActive: Bool {
        mode == .dictionary || isApplicationDictionaryActive
    }

    var isApplicationDictionaryActive: Bool {
        mode == .applications && applicationQueryRoute.dictionaryTerm != nil
    }

    var placeholder: String {
        mode.placeholder
    }

    var resultCount: Int {
        switch mode {
        case .applications:
            switch applicationQueryRoute {
            case .calculator, .dictionary:
                return toolItems.count
            case .applications:
                return filteredItemIDs.count
            }
        case .dictionary, .agenda:
            if mode == .agenda {
                return filteredAgendaNotes.count
            }
            return toolItems.count
        case .files:
            return MainActor.assumeIsolated {
                fileBrowserModel.entries.count
            }
        }
    }

    var canClearHistory: Bool {
        isApplicationCalculatorActive && !calculationHistoryStore.calculations.isEmpty
    }

    var emptyMessage: String? {
        switch mode {
        case .applications:
            if isApplicationCalculatorActive {
                return toolItems.isEmpty ? "No calculation history" : nil
            }
            if isApplicationDictionaryActive {
                return toolItems.isEmpty && !isDictionaryLookupLoading ? "No dictionary matches" : nil
            }
            if filteredItemIDs.isEmpty {
                if isIndexing && appRowStore.isEmpty {
                    return "Loading apps"
                }
                return inputIsBlank ? "No launchable items found" : "No matches"
            }
        case .dictionary:
            if toolItems.isEmpty, !inputIsBlank {
                return "No dictionary matches"
            }
        case .files:
            if MainActor.assumeIsolated({ fileBrowserModel.entries.isEmpty }) {
                return "No files"
            }
        case .agenda:
            if inputIsBlank, agendaNotes.isEmpty {
                return "Agenda scratchpad"
            }
            if !inputIsBlank, filteredAgendaNotes.isEmpty {
                return "No agenda matches"
            }
        }

        return nil
    }

    var inputIsBlank: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func show(mode: LauncherMode) {
        isShowingSettings = false
        isShowingHelp = false
        dictionaryPreview = nil
        dictionaryPreviewLoadingTerm = nil
        calculatorResultFeedback = nil
        applicationQuery = ""
        dictionaryQuery = ""
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

    func setWindowKeyState(_ isWindowKey: Bool) {
        guard self.isWindowKey != isWindowKey else { return }
        self.isWindowKey = isWindowKey
    }

    func prepareFileBrowserMode() {
        guard mode == .files else { return }
        let model = activateFileBrowserModel()
        selectedIndex = MainActor.assumeIsolated {
            model.selectedIndex
        }
    }

    func queryDidChange() {
        cancelDictionaryPreview()
        if mode == .applications {
            calculatorResultFeedback = nil
        }
        storeCurrentQuery()
        applyCurrentMode(preservePreviousOnEmpty: true)
    }

    func cancelDictionaryPreview() {
        pendingDictionaryPreviewTask?.cancel()
        pendingDictionaryPreviewTask = nil
        dictionaryPreviewGeneration += 1
        dictionaryPreview = nil
        dictionaryPreviewLoadingTerm = nil
    }

    func insertTextInput(_ character: Character) {
        query.append(character)
        queryDidChange()
    }

    func handle(command: LauncherCommand) -> Bool {
        switch command {
        case .up:
            if mode == .agenda {
                return handleAgendaCommand(.agendaMoveSelection(.up))
            }
            if mode == .files {
                return handleFileBrowserCommand(command)
            }
            moveSelection(by: -1)
        case .down:
            if mode == .agenda {
                return handleAgendaCommand(.agendaMoveSelection(.down))
            }
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
            if mode == .agenda {
                return handleAgendaCommand(command)
            }
            if mode == .files {
                return handleFileBrowserCommand(command)
            }
            activateSelected()
        case .close:
            if dictionaryRouteIsActive, dictionaryPreview != nil {
                cancelDictionaryPreview()
                return true
            }
            if mode == .agenda,
               (openedAgendaNote != nil || isConfirmingAgendaRemoval) {
                return handleAgendaCommand(command)
            }
            if mode == .files, fileBrowserFocusState != .browse {
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
            return switchMode(mode.previousMode)
        case .nextMode:
            return switchMode(mode.nextMode)
        case .clearHistory:
            clearHistory()
        case .togglePin:
            if mode == .files {
                return handleFileBrowserCommand(command)
            }
            isPinned.toggle()
        case .createAgendaItem, .removeAgendaSelection, .saveAgendaNote:
            guard mode == .agenda else { return false }
            return handleAgendaCommand(command)
        case .agendaMoveSelection:
            guard mode == .agenda else { return false }
            return handleAgendaCommand(command)
        case .prepareSpaceInteraction:
            if dictionaryRouteIsActive {
                return true
            }
            guard mode == .files else { return false }
            return handleFileBrowserCommand(command)
        case .space:
            if dictionaryRouteIsActive {
                insertTextInput(" ")
                return true
            }
            guard mode == .files else { return false }
            return handleFileBrowserCommand(command)
        case .beginSpaceHold:
            if dictionaryRouteIsActive {
                return beginDictionaryPreview()
            }
            guard mode == .files else { return false }
            return handleFileBrowserCommand(command)
        case .endSpaceHold:
            if dictionaryRouteIsActive {
                cancelDictionaryPreview()
                return true
            }
            guard mode == .files else { return false }
            return handleFileBrowserCommand(command)
        case .left, .right, .shiftSpace,
                .alphaNumeric, .shiftAlphaNumeric, .beginPinnedFocus, .endPinnedFocus, .historyBack, .historyForward:
            guard mode == .files else { return false }
            return handleFileBrowserCommand(command)
        }

        return true
    }

    func reindex() {
        cancelPendingApplicationFilter()
        cancelPendingDictionaryLookup()
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
        exclusionStore.exclude(item)
        rebuildVisibleItems()
        applyFilter()
    }

    func clearHistory() {
        cancelPendingDictionaryLookup()
        calculationHistoryStore.clear()
        applyToolsResults(scheduleHistory: false)
    }

    func removeDictionaryHistory(_ item: ToolItem) {
        guard item.kind == .dictionaryHistory else { return }
        cancelPendingDictionaryLookup()
        dictionaryHistoryStore.remove(term: item.title)
        applyToolsResults(scheduleHistory: false)
    }

    func cancelPendingCalculationHistory() {
        pendingCalculationHistoryTimer?.invalidate()
        pendingCalculationHistoryTimer = nil
        pendingCalculationHistoryExpression = nil
        pendingCalculationHistoryResult = nil
    }

    private func cancelPendingDictionaryLookup() {
        dictionaryLookupGeneration += 1
        pendingDictionaryLookupTask?.cancel()
        pendingDictionaryLookupTask = nil
        isDictionaryLookupLoading = false
    }

    private func cancelPendingApplicationFilter() {
        applicationFilterGeneration += 1
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
        switch mode {
        case .applications:
            switch applicationQueryRoute {
            case .calculator, .dictionary:
                cancelPendingApplicationFilter()
                applyToolsResults()
            case .applications:
                cancelPendingDictionaryLookup()
                cancelPendingCalculationHistory()
                if toolItems.contains(where: { $0.kind == .calculation || $0.kind == .calculationHistory || $0.kind == .dictionary || $0.kind == .dictionaryHistory || $0.kind == .message }) {
                    toolItems = []
                }
                if appRowStore.visibleIDs.isEmpty, !appRowStore.isEmpty {
                    rebuildVisibleItems()
                }
                applyApplicationFilter(preservePreviousOnEmpty: preservePreviousOnEmpty)
            }
        case .dictionary:
            applyToolsResults()
        case .agenda:
            cancelPendingCalculationHistory()
            cancelPendingDictionaryLookup()
            toolItems = []
            clampAgendaSelection()
        case .files:
            cancelPendingCalculationHistory()
            cancelPendingDictionaryLookup()
            toolItems = []
            selectedIndex = MainActor.assumeIsolated {
                fileBrowserModel.selectedIndex
            }
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
        applicationFilterGeneration += 1
        let generation = applicationFilterGeneration
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
                      self.applicationFilterGeneration == generation,
                      normalized(self.query) == cacheKey else {
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
        _ = dictionaryHistoryItems()
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

    private static func warmFilterEntries(
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

    static func filterIDs(
        _ ids: [AppRowID],
        rowStore: ApplicationRowStore,
        normalizedQuery: String
    ) -> [AppRowID] {
        guard !normalizedQuery.isEmpty else {
            return ids
        }

        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return ids.compactMap { id -> (AppRowID, Int)? in
            guard let item = rowStore.item(for: id),
                  tokens.allSatisfy({ item.searchText.contains($0) }) else {
                return nil
            }

            return (id, score(item: item, tokens: tokens))
        }
        .sorted {
            if $0.1 == $1.1 {
                let left = rowStore.item(for: $0.0)?.title ?? ""
                let right = rowStore.item(for: $1.0)?.title ?? ""
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            return $0.1 > $1.1
        }
        .map(\.0)
    }

    static func filter(_ items: [LaunchItem], normalizedQuery: String) -> [LaunchItem] {
        guard !normalizedQuery.isEmpty else {
            return items
        }

        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return items.indices.compactMap { index -> (Int, Int)? in
            let item = items[index]
            guard tokens.allSatisfy({ item.searchText.contains($0) }) else {
                return nil
            }
            return (index, score(item: item, tokens: tokens))
        }
        .sorted {
            if $0.1 == $1.1 {
                return items[$0.0].title.localizedStandardCompare(items[$1.0].title) == .orderedAscending
            }
            return $0.1 > $1.1
        }
        .map { items[$0.0] }
    }

    private static func score(item: LaunchItem, tokens: [String]) -> Int {
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
        return score
    }

    private func applyToolsResults(scheduleHistory: Bool = true) {
        let trimmedQuery = toolQueryForCurrentMode()
        cancelPendingCalculationHistory()

        switch ToolResultsSnapshotPolicy.update(for: mode, query: query) {
        case .immediate:
            cancelPendingDictionaryLookup()
            applyToolResultsSnapshot(
                makeToolItems(for: trimmedQuery, scheduleHistory: scheduleHistory),
                selectLiveCalculation: scheduleHistory
            )
        case let .deferred(delayNanoseconds):
            applyDeferredToolResults(
                for: trimmedQuery,
                delayNanoseconds: delayNanoseconds,
                selectLiveCalculation: scheduleHistory
            )
        }
    }

    private func applyDeferredToolResults(
        for trimmedQuery: String,
        delayNanoseconds: UInt64,
        selectLiveCalculation: Bool
    ) {
        guard dictionaryRouteIsActive else { return }

        dictionaryLookupGeneration += 1
        let generation = dictionaryLookupGeneration
        let lookup = dictionaryLookup
        if toolItems.contains(where: { $0.kind == .calculation || $0.kind == .calculationHistory }) {
            toolItems = []
            selectedIndex = 0
        }
        isDictionaryLookupLoading = true
        pendingDictionaryLookupTask?.cancel()
        pendingDictionaryLookupTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            let results = await Task.detached(priority: .userInitiated) {
                lookup(trimmedQuery)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                self?.applyDictionaryLookupResults(
                    results,
                    query: trimmedQuery,
                    generation: generation,
                    selectLiveCalculation: selectLiveCalculation
                )
            }
        }
    }

    private func makeToolItems(for trimmedQuery: String, scheduleHistory: Bool) -> [ToolItem] {
        switch mode {
        case .applications:
            if isApplicationDictionaryActive {
                return trimmedQuery.isEmpty ? dictionaryHistoryItems() : toolItems
            }
            guard isApplicationCalculatorActive else { return [] }
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
                return dictionaryHistoryItems()
            }

            return toolItems
        case .files, .agenda:
            return []
        }
    }

    private func makeDictionaryToolItems(for query: String, results: [DictionaryResult]) -> [ToolItem] {
        if results.isEmpty {
            return [
                ToolItem(
                    title: "No dictionary matches",
                    subtitle: query,
                    copyText: nil,
                    kind: .message
                )
            ]
        }

        return results.map { result in
            ToolItem(
                title: result.term,
                subtitle: singleLine(result.definition),
                copyText: nil,
                kind: .dictionary,
                previewText: result.definition
            )
        }
    }

    private func applyDictionaryLookupResults(
        _ results: [DictionaryResult],
        query: String,
        generation: Int,
        selectLiveCalculation: Bool
    ) {
        guard dictionaryRouteIsActive,
              dictionaryLookupGeneration == generation,
              toolQueryForCurrentMode() == query else {
            return
        }

        pendingDictionaryLookupTask = nil
        isDictionaryLookupLoading = false
        applyToolResultsSnapshot(
            makeDictionaryToolItems(for: query, results: results),
            selectLiveCalculation: selectLiveCalculation
        )
    }

    private func applyToolResultsSnapshot(_ nextItems: [ToolItem], selectLiveCalculation: Bool) {
        toolItems = nextItems
        if selectLiveCalculation, isApplicationCalculatorActive, toolItems.first?.kind == .calculation {
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
                kind: .calculationHistory,
                inputText: entry.expression
            )
        }
    }

    private func dictionaryHistoryItems() -> [ToolItem] {
        dictionaryHistoryStore.words.map { entry in
            ToolItem(
                title: entry.term,
                subtitle: "Opened \(Self.calculationHistoryDateFormatter.string(from: entry.date))",
                copyText: nil,
                kind: .dictionaryHistory
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

        if refreshResults, isApplicationCalculatorActive {
            applyToolsResults(scheduleHistory: false)
        }
    }

    private func toolQueryForCurrentMode() -> String {
        if mode == .applications {
            switch applicationQueryRoute {
            case let .calculator(expression): return expression
            case let .dictionary(term): return term
            case .applications: break
            }
        }

        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearInputOrHide() {
        cancelDictionaryPreview()
        if inputIsBlank {
            if isPinned {
                isPinned = false
            }
            hideAction?()
            return
        }

        query = ""
        storeCurrentQuery()
        cancelPendingDictionaryLookup()
        applyCurrentMode()
    }

    private func storeCurrentQuery() {
        switch mode {
        case .applications:
            applicationQuery = query
        case .dictionary:
            dictionaryQuery = query
        case .files:
            break
        case .agenda:
            agendaQuery = query
        }
    }

    private func storedQuery(for mode: LauncherMode) -> String {
        switch mode {
        case .applications:
            return applicationQuery
        case .dictionary:
            return dictionaryQuery
        case .files:
            return ""
        case .agenda:
            return agendaQuery
        }
    }

    private func switchMode(_ nextMode: LauncherMode) -> Bool {
        if mode != nextMode {
            modeWillSwitchAction?(mode, nextMode)
        }
        cancelPendingDictionaryLookup()
        pendingDictionaryPreviewTask?.cancel()
        pendingDictionaryPreviewTask = nil
        cancelPendingApplicationFilter()
        cancelDictionaryPreview()
        calculatorResultFeedback = nil
        storeCurrentQuery()
        mode = nextMode
        query = storedQuery(for: nextMode)
        selectedIndex = 0
        publishLightweightModeSnapshot(for: nextMode)
        scheduleModeSnapshot(for: nextMode)
        return true
    }

    private func publishLightweightModeSnapshot(for mode: LauncherMode) {
        switch mode {
        case .applications:
            break
        case .dictionary, .files, .agenda:
            toolItems = []
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

    func rememberAgendaNote(url: URL) {
        agendaStore.rememberNote(url: url)
        syncAgendaSnapshot()
        agendaSelectedNoteIndex = 0
    }

    func confirmAgendaRemoval() {
        guard filteredAgendaNotes.indices.contains(agendaSelectedNoteIndex) else {
            cancelAgendaRemoval()
            return
        }
        agendaStore.removeNote(id: filteredAgendaNotes[agendaSelectedNoteIndex].id)
        syncAgendaSnapshot()
        cancelAgendaRemoval()
    }

    func cancelAgendaRemoval() {
        isConfirmingAgendaRemoval = false
    }

    private func syncAgendaSnapshot() {
        agendaNotes = agendaStore.notes
        clampAgendaSelection()
    }

    private func handleAgendaCommand(_ command: LauncherCommand) -> Bool {
        switch command {
        case .open:
            if isConfirmingAgendaRemoval {
                confirmAgendaRemoval()
                return true
            }
            guard filteredAgendaNotes.indices.contains(agendaSelectedNoteIndex) else {
                openAgendaNoteAction?()
                return true
            }
            openAgendaNote(filteredAgendaNotes[agendaSelectedNoteIndex])
            return true
        case .createAgendaItem:
            openAgendaNoteAction?()
            return true
        case .removeAgendaSelection:
            isConfirmingAgendaRemoval = true
            return true
        case .saveAgendaNote:
            saveOpenedAgendaNote()
            return true
        case .close:
            if isConfirmingAgendaRemoval {
                cancelAgendaRemoval()
                return true
            }
            if isAgendaNoteSearchVisible {
                isAgendaNoteSearchVisible = false
                return true
            }
            saveOpenedAgendaNote()
            openedAgendaNote = nil
            agendaOpenNoteText = ""
            isAgendaNoteSearchVisible = false
            return true
        case let .agendaMoveSelection(direction):
            moveAgendaSelection(direction)
            return true
        default:
            return false
        }
    }

    private func moveAgendaSelection(_ direction: AgendaNavigationDirection) {
        switch direction {
        case .left, .right:
            break
        case .up:
            agendaSelectedNoteIndex = max(agendaSelectedNoteIndex - 1, 0)
        case .down:
            agendaSelectedNoteIndex = min(agendaSelectedNoteIndex + 1, max(filteredAgendaNotes.count - 1, 0))
        }
        clampAgendaSelection()
    }

    private func clampAgendaSelection() {
        agendaSelectedNoteIndex = min(max(agendaSelectedNoteIndex, 0), max(filteredAgendaNotes.count - 1, 0))
    }

    private func openAgendaNote(_ note: AgendaNoteReference) {
        openedAgendaNote = note
        agendaOpenNoteText = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        isAgendaNoteSearchVisible = false
    }

    private func saveOpenedAgendaNote() {
        guard let openedAgendaNote else { return }
        try? agendaOpenNoteText.write(to: openedAgendaNote.url, atomically: true, encoding: .utf8)
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
        refreshDictionaryPreviewForCurrentSelection()
    }

    private func moveSelection(to index: Int, anchor: SelectionScrollAnchor) {
        guard resultCount > 0 else { return }
        selectedIndex = max(0, min(resultCount - 1, index))
        requestSelectionScroll(anchor: anchor)
        refreshDictionaryPreviewForCurrentSelection()
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
            switch applicationQueryRoute {
            case .calculator, .dictionary:
                guard selectedIndex >= 0, selectedIndex < toolItems.count else { return }
                activate(toolItems[selectedIndex])
                return
            case .applications:
                break
            }

            guard selectedIndex >= 0, selectedIndex < filteredItemIDs.count,
                  let item = appRowStore.item(for: filteredItemIDs[selectedIndex]) else { return }
            if !isPinned {
                hideAction?()
            }
            launch(item)
        case .dictionary:
            guard selectedIndex >= 0, selectedIndex < toolItems.count else { return }
            activate(toolItems[selectedIndex])
        case .files:
            MainActor.assumeIsolated {
                fileBrowserModel.handle(.open)
            }
        case .agenda:
            break
        }
    }

    private func launch(_ item: LaunchItem) {
        switch item.launchTarget {
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

    private func activate(_ item: ToolItem) {
        let activatedDictionaryHistory = item.kind == .dictionaryHistory

        switch item.kind {
        case .calculation:
            activateLiveCalculation(item)
            return
        case .calculationHistory:
            restoreCalculationHistoryExpression(item)
            return
        case .dictionary, .dictionaryHistory:
            dictionaryHistoryStore.add(term: item.title)
            openDictionary(term: item.title)
        case .message:
            return
        }

        if mode == .dictionary, inputIsBlank {
            applyToolsResults(scheduleHistory: false)
            if activatedDictionaryHistory {
                selectedIndex = 0
                requestSelectionScroll(anchor: .top)
            }
        }

        if !isPinned {
            hideAction?()
        }
    }

    private func restoreCalculationHistoryExpression(_ item: ToolItem) {
        guard let inputText = item.inputText else { return }
        calculatorResultFeedback = nil
        query = "=\(inputText)"
        storeCurrentQuery()
        applyToolsResults(scheduleHistory: false)
        selectedIndex = 0
        requestSelectionScroll(anchor: .top)
    }

    private func activateLiveCalculation(_ item: ToolItem) {
        guard let result = item.copyText else { return }
        commitPendingCalculationHistory(refreshResults: false)
        copyToPasteboard(result)
        calculatorResultFeedbackID += 1
        calculatorResultFeedback = CalculatorResultFeedback(id: calculatorResultFeedbackID, result: result)
        selectedIndex = 0
        requestSelectionScroll(anchor: .top)
    }

    private func beginDictionaryPreview() -> Bool {
        guard dictionaryRouteIsActive,
              toolItems.indices.contains(selectedIndex) else {
            return false
        }

        let item = toolItems[selectedIndex]
        dictionaryPreviewGeneration += 1
        let generation = dictionaryPreviewGeneration
        pendingDictionaryPreviewTask?.cancel()
        guard let preview = dictionaryPreview(for: item) else {
            guard item.kind == .dictionaryHistory else { return false }
            return startDictionaryPreviewLookup(for: item, generation: generation)
        }

        dictionaryPreview = preview
        dictionaryPreviewLoadingTerm = nil
        return true
    }

    private func refreshDictionaryPreviewForCurrentSelection() {
        guard dictionaryRouteIsActive,
              dictionaryPreview != nil || dictionaryPreviewLoadingTerm != nil,
              toolItems.indices.contains(selectedIndex) else {
            return
        }
        pendingDictionaryPreviewTask?.cancel()
        dictionaryPreviewLoadingTerm = nil
        dictionaryPreviewGeneration += 1
        let item = toolItems[selectedIndex]
        let hasPreviewText = item.previewText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if item.kind == .dictionaryHistory && !hasPreviewText {
            _ = startDictionaryPreviewLookup(for: item, generation: dictionaryPreviewGeneration)
        } else if let preview = dictionaryPreview(for: item) {
            dictionaryPreview = preview
        } else {
            dictionaryPreview = nil
        }
    }

    private func startDictionaryPreviewLookup(for item: ToolItem, generation: Int) -> Bool {
        dictionaryPreview = nil
        dictionaryPreviewLoadingTerm = item.title
        let lookup = dictionaryLookup
        pendingDictionaryPreviewTask = Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) {
                lookup(item.title)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.dictionaryRouteIsActive,
                      self.dictionaryPreviewGeneration == generation,
                      self.toolItems.indices.contains(self.selectedIndex),
                      self.toolItems[self.selectedIndex].title == item.title else { return }
                let previewItem = ToolItem(title: item.title, subtitle: item.subtitle, copyText: nil, kind: .dictionary, previewText: results.first?.definition)
                self.dictionaryPreview = self.dictionaryPreview(for: previewItem)
                self.dictionaryPreviewLoadingTerm = nil
                self.pendingDictionaryPreviewTask = nil
            }
        }
        return true
    }

    private func dictionaryPreview(for item: ToolItem) -> DictionaryDefinitionPreview? {
        switch item.kind {
        case .dictionary, .dictionaryHistory:
            if let previewText = item.previewText,
               !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return DictionaryDefinitionPreview(term: item.title, definition: previewText)
            }

            guard item.kind == .dictionaryHistory else {
                return nil
            }

            return nil
        case .calculation, .calculationHistory, .message:
            return nil
        }
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value else { return }
        pasteboardCopyHandler(value)
    }

    private static func copyStringToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func openDictionary(term: String) {
        dictionaryOpenHandler(term)
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
