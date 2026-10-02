import AppKit
import Combine
import Foundation

@MainActor
final class FileBrowserModel: ObservableObject {
    @Published private(set) var currentDirectory: URL
    @Published private(set) var entries: [FileBrowserEntry] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var selectedURLs: [URL] = []
    @Published private(set) var focusState: FileBrowserFocusState = .browse
    @Published private(set) var wobbleReason: FileBrowserWobbleReason?
    @Published private(set) var wobbleEvent: FileBrowserWobbleEvent?
    @Published private(set) var navigationTransition: FileBrowserNavigationTransition?
    @Published private(set) var selectionScrollEvent: FileBrowserSelectionScrollEvent?
    @Published private(set) var sort: FileBrowserSort
    @Published private(set) var foldersFirst: Bool
    @Published private(set) var pinnedDirectories: [URL] = []
    @Published private(set) var focusedPinnedIndex = 0
    @Published private(set) var focusedActionIndex = 0
    @Published private(set) var focusedConflictResolution: FileBrowserConflictResolution = .keepBoth
    @Published private(set) var directorySnapshots: [FileBrowserDirectorySnapshot] = []
    @Published private(set) var pendingActionIntent: FileBrowserActionIntent?
    @Published private(set) var renameState: FileBrowserRenameState?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isLoadingEntries = false
    @Published private(set) var isPerformingOperation = false

    private let fileSystem: FileSystemClientProtocol
    private let store: FileBrowserPersisting
    private let directoryStream: FileBrowserDirectoryStreaming
    private let directoryObserver: FileBrowserDirectoryObserving?
    private let fileServices: FileBrowserNativeServicing
    private let operationWorker: FileBrowserWorking
    private var selectionAnchor: Int?
    private var recentTraversalChain: [URL]
    private var nextWobbleID = 0
    private var nextNavigationTransitionID = 0
    private var nextSelectionScrollID = 0
    private var directoryLoadGeneration = 0
    private var rememberedSelectionByDirectory: [URL: URL] = [:]
    private var rememberedDirectoryOrder: [URL] = []
    private var directoryBackStack: [URL] = []
    private var directoryForwardStack: [URL] = []
    private var pendingSpaceInteractionURL: URL?
    private var snapshotEntryCache: [DirectorySnapshotCacheKey: [FileBrowserEntry]] = [:]
    private var pendingSnapshotRequests: Set<DirectorySnapshotCacheKey> = []
    private var directoryObservation: FileBrowserDirectoryObservation?
    private var observedDirectory: URL?
    private var isActive = true
    private var observationRefreshTask: Task<Void, Never>?

    var selectedEntry: FileBrowserEntry? {
        guard selectedIndex >= 0, selectedIndex < entries.count else { return nil }
        return entries[selectedIndex]
    }

    var activeSelectionURLs: [URL] {
        if selectedURLs.isEmpty, let url = selectedEntry?.url {
            return [url]
        }
        return selectedURLs
    }

    var focusedPinnedURL: URL? {
        guard focusedPinnedIndex >= 0, focusedPinnedIndex < sidebarDirectories.count else { return nil }
        return sidebarDirectories[focusedPinnedIndex]
    }

    var sidebarDirectories: [URL] {
        let mountsDirectory = URL(fileURLWithPath: "/Volumes", isDirectory: true).standardizedFileURL
        let directories = pinnedDirectories + [mountsDirectory]
        return directories.reduce(into: []) { result, directory in
            guard !result.contains(where: { $0.standardizedFileURL.path == directory.standardizedFileURL.path }) else {
                return
            }
            result.append(directory.standardizedFileURL)
        }
    }

    var availableActions: [FileBrowserAction] {
        if selectedURLs.isEmpty,
           selectedEntry?.isMount == true,
           selectedEntry?.canUnmount == true {
            return [.open, .revealInFinder, .copyPath, .unmount]
        }

        if activeSelectionURLs.count > 1 {
            return [.batchRename, .copyPaths, .copy, .move, .moveToTrash]
        }

        return [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash]
    }

    var focusableActions: [FileBrowserAction] {
        availableActions
    }

    init(
        fileSystem: FileSystemClientProtocol = FileSystemClient(),
        store: FileBrowserPersisting = FileBrowserStore(),
        directoryStream: FileBrowserDirectoryStreaming? = nil,
        directoryObserver: FileBrowserDirectoryObserving? = FileBrowserDirectoryWatcher(),
        fileServices: FileBrowserNativeServicing = MacFileServices(),
        operationWorker: FileBrowserWorking? = nil,
        startDirectory: URL? = nil
    ) {
        self.fileSystem = fileSystem
        self.store = store
        self.directoryStream = directoryStream ?? FileBrowserDirectoryStream(fileSystem: fileSystem, accessStore: store)
        self.directoryObserver = directoryObserver
        self.fileServices = fileServices
        self.operationWorker = operationWorker ?? FileBrowserWorker()
        self.sort = store.state.sort
        self.foldersFirst = store.state.foldersFirst
        self.pinnedDirectories = store.state.pinnedDirectories
        self.recentTraversalChain = Array(store.state.traversalChain.prefix(FileBrowserRetentionPolicy.historyLimit))
        self.rememberedDirectoryOrder = store.state.rememberedSelections.suffix(FileBrowserRetentionPolicy.selectionLimit).map { $0.directory.standardizedFileURL }
        self.rememberedSelectionByDirectory = store.state.rememberedSelections.suffix(FileBrowserRetentionPolicy.selectionLimit).reduce(into: [:]) { selections, item in
            selections[item.directory.standardizedFileURL] = item.selection.standardizedFileURL
        }
        self.currentDirectory = store.state.lastDirectory ?? startDirectory ?? fileSystem.homeDirectory()
        store.onPersistenceError = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pinnedDirectories = self.store.state.pinnedDirectories
                self.clampFocusedPinnedIndex()
                self.statusMessage = message
            }
        }
        observeCurrentDirectory()
        reloadEntries(fallbackToHomeOnFailure: true)
    }

    deinit {
        directoryObservation?.cancel()
        observationRefreshTask?.cancel()
    }

    func flushPersistence(completion: @escaping () -> Void) {
        guard isPerformingOperation else {
            store.flush(completion: completion)
            return
        }
        // Retain the model until an approved operation completes, without blocking the UI actor.
        Task { @MainActor in
            while isPerformingOperation {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            store.flush(completion: completion)
        }
    }

    /// Main integrates this with launcher visibility, mode, settings, and help presentation.
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if active {
            observeCurrentDirectory()
            reloadEntries(selecting: rememberedSelection(in: currentDirectory))
        } else {
            directoryObservation?.cancel()
            directoryObservation = nil
            observedDirectory = nil
            observationRefreshTask?.cancel()
            observationRefreshTask = nil
            directoryStream.cancelPendingLoads()
            directoryLoadGeneration += 1
            isLoadingEntries = false
        }
    }

    func handle(_ command: LauncherCommand) {
        guard !isPerformingOperation else { return }
        switch command {
        case .up:
            if focusState == .pinnedItems {
                moveFocusedPin(by: -1)
            } else if focusState == .previewActions {
                moveFocusedAction(by: -1)
            } else if isConflictConfirmation {
                moveConflictResolution(by: -1)
            } else {
                moveSelection(by: -1)
            }
        case .down:
            if focusState == .pinnedItems {
                moveFocusedPin(by: 1)
            } else if focusState == .previewActions {
                moveFocusedAction(by: 1)
            } else if isConflictConfirmation {
                moveConflictResolution(by: 1)
            } else {
                moveSelection(by: 1)
            }
        case .top:
            if focusState == .pinnedItems {
                moveFocusedPin(to: 0)
            } else {
                moveSelection(to: 0, anchor: .top)
            }
        case .bottom:
            if focusState == .pinnedItems {
                moveFocusedPin(to: sidebarDirectories.count - 1)
            } else {
                moveSelection(to: entries.count - 1, anchor: .bottom)
            }
        case .left:
            if focusState == .pinnedItems {
                break
            } else {
                moveToParent()
            }
        case .right:
            if focusState == .pinnedItems {
                openFocusedPin()
            } else {
                enterSelectedDirectoryOrWobble()
            }
        case .prepareSpaceInteraction:
            prepareSpaceInteraction()
        case .space:
            toggleSelection()
        case .shiftSpace:
            rangeSelect()
        case let .alphaNumeric(character):
            if focusState == .browse {
                cycle(toFirstCharacter: character, direction: .forward)
            } else if focusState == .pinnedItems {
                cyclePinnedItems(toFirstCharacter: character, direction: .forward)
            }
        case let .shiftAlphaNumeric(character):
            if focusState == .browse {
                cycle(toFirstCharacter: character, direction: .backward)
            } else if focusState == .pinnedItems {
                cyclePinnedItems(toFirstCharacter: character, direction: .backward)
            }
        case .beginSpaceHold:
            beginQuickLook()
        case .endSpaceHold:
            endQuickLook()
        case .open:
            if focusState == .pinnedItems {
                openFocusedPin()
            } else if focusState == .previewActions {
                performFocusedAction()
            } else if case let .transferPending(transfer) = focusState {
                focusState = .confirming(.transfer(transfer, destination: currentDirectory))
            } else if focusState == .renaming {
                confirmRename()
            } else if case let .confirming(confirmation) = focusState {
                confirm(confirmation)
            } else {
                focusedActionIndex = 0
                focusState = .previewActions
            }
        case .close:
            closeFocusedState()
        case .togglePin:
            togglePinSelectedItem()
        case .beginPinnedFocus:
            beginPinnedFocus()
        case .endPinnedFocus:
            endPinnedFocus()
        case .historyBack:
            moveDirectoryHistoryBack()
        case .historyForward:
            moveDirectoryHistoryForward()
        default:
            break
        }
    }

    func startTransfer(_ kind: FileBrowserTransferKind) {
        guard !isPerformingOperation else { return }
        let urls = activeSelectionURLs
        guard !urls.isEmpty else { return }
        pendingActionIntent = nil
        switch kind {
        case .copy:
            focusState = .transferPending(.copy(urls))
        case .move:
            focusState = .transferPending(.move(urls))
        }
    }

    func requestTrashConfirmation() {
        guard !isPerformingOperation else { return }
        let urls = activeSelectionURLs
        guard !urls.isEmpty else { return }
        pendingActionIntent = nil
        focusState = .confirming(.trash(urls, step: 1))
    }

    func confirmTrashStep() {
        guard case let .confirming(.trash(urls, step)) = focusState else { return }
        focusState = .confirming(.trash(urls, step: min(step + 1, 2)))
    }

    func togglePin(_ url: URL) {
        guard !isPerformingOperation else { return }
        if pinnedDirectories.contains(url) {
            pinnedDirectories.removeAll { $0 == url }
        } else {
            guard pinnedDirectories.count < FileBrowserRetentionPolicy.pinLimit else {
                statusMessage = "Files supports up to \(FileBrowserRetentionPolicy.pinLimit) pins."
                return
            }
            pinnedDirectories.append(url)
        }
        clampFocusedPinnedIndex()
        persist()
    }

    func setSort(_ nextSort: FileBrowserSort) {
        guard !isPerformingOperation else { return }
        guard sort != nextSort else { return }
        let preferredSelection = selectedEntry?.url ?? rememberedSelection(in: currentDirectory)
        sort = nextSort
        reloadEntries(selecting: preferredSelection)
    }

    func setFoldersFirst(_ isEnabled: Bool) {
        guard !isPerformingOperation else { return }
        guard foldersFirst != isEnabled else { return }
        let preferredSelection = selectedEntry?.url ?? rememberedSelection(in: currentDirectory)
        foldersFirst = isEnabled
        reloadEntries(selecting: preferredSelection)
    }

    func setRenameText(_ text: String) {
        guard var renameState else { return }
        renameState.proposedName = text
        self.renameState = renameState
    }

    func openPinnedDirectory(_ url: URL) {
        guard !isPerformingOperation else { return }
        openPinnedURL(url)
    }

    func entry(for url: URL) -> FileBrowserEntry? {
        let standardizedURL = url.standardizedFileURL
        return directorySnapshots
            .lazy
            .flatMap(\.entries)
            .first { $0.url.standardizedFileURL == standardizedURL }
    }

    @discardableResult
    func loadPreviewThumbnail(
        for url: URL,
        size: CGSize,
        scale: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) -> FileBrowserCancellation {
        fileServices.loadPreviewThumbnail(for: url, size: size, scale: scale, completion: completion)
    }

    func icon(for url: URL) -> NSImage {
        fileServices.icon(for: url)
    }

    func performFocusedAction() {
        guard !isPerformingOperation else { return }
        guard focusState == .previewActions else { return }
        let actions = focusableActions
        guard !actions.isEmpty else { return }
        let action = actions[max(0, min(actions.count - 1, focusedActionIndex))]
        pendingActionIntent = nil
        statusMessage = nil
        switch action {
        case .open:
            if let url = activeSelectionURLs.first {
                performServiceAction(recoveringTo: .previewActions) {
                    try fileServices.open(url)
                    focusState = .browse
                }
            }
        case .rename, .batchRename:
            beginRename(action == .batchRename ? .batch : .single)
        case .revealInFinder:
            let urls = activeSelectionURLs
            performServiceAction(recoveringTo: .previewActions) {
                try fileServices.revealInFinder(urls)
                focusState = .browse
            }
        case .copyPath, .copyPaths:
            let urls = activeSelectionURLs
            performServiceAction(recoveringTo: .previewActions) {
                try fileServices.copyPathsToPasteboard(urls)
                focusState = .browse
            }
        case .copy:
            startTransfer(.copy)
        case .move:
            startTransfer(.move)
        case .moveToTrash:
            requestTrashConfirmation()
        case .unmount:
            guard let url = selectedEntry?.url,
                  selectedEntry?.isMount == true,
                  selectedEntry?.canUnmount == true else {
                return
            }
            focusState = .confirming(.unmount(url))
        }
    }

    func moveFocusedAction(by delta: Int) {
        guard focusState == .previewActions, !focusableActions.isEmpty else { return }
        focusedActionIndex = max(0, min(focusableActions.count - 1, focusedActionIndex + delta))
    }

    private var isConflictConfirmation: Bool {
        if case .confirming(.conflict) = focusState {
            return true
        }
        return false
    }

    private func beginRename(_ mode: FileBrowserRenameMode) {
        let urls = activeSelectionURLs
        guard !urls.isEmpty else { return }
        let proposedName: String
        switch mode {
        case .single:
            proposedName = urls[0].lastPathComponent
        case .batch:
            proposedName = "Untitled"
        }
        renameState = FileBrowserRenameState(mode: mode, urls: urls, proposedName: proposedName)
        focusState = .renaming
    }

    private func confirmRename() {
        guard let renameState else { return }
        let services = fileServices
        performBlockingAction(recoveringTo: .renaming, operation: {
            switch renameState.mode {
            case .single:
                _ = try services.rename(renameState.urls[0], to: renameState.proposedName)
            case .batch:
                _ = try services.batchRename(renameState.urls, baseName: renameState.proposedName)
            }
        }) { model in
            model.renameState = nil
            model.selectedURLs = []
            model.focusState = .browse
            model.reloadEntries()
        }
    }

    private func confirm(_ confirmation: FileBrowserConfirmation) {
        statusMessage = nil
        switch confirmation {
        case let .transfer(transfer, destination):
            confirmTransfer(transfer, destination: destination, conflict: .keepBoth, checkingConflicts: true)
        case let .conflict(transfer, destination, _):
            if focusedConflictResolution == .cancel {
                focusState = .browse
            } else {
                confirmTransfer(transfer, destination: destination, conflict: focusedConflictResolution, checkingConflicts: false)
            }
        case let .trash(urls, step):
            if step < 2 {
                focusState = .confirming(.trash(urls, step: 2))
            } else {
                let services = fileServices
                performBlockingAction(recoveringTo: .confirming(confirmation), operation: {
                    try services.trash(urls)
                }) { model in
                    model.selectedURLs = []
                    model.focusState = .browse
                    model.reloadEntries()
                }
            }
        case let .unmount(url):
            let services = fileServices
            performBlockingAction(recoveringTo: .confirming(confirmation), operation: {
                try services.unmount(url)
            }) { model in
                model.selectedURLs = []
                model.focusState = .browse
                model.reloadEntries()
            }
        }
    }

    private func confirmTransfer(
        _ transfer: FileBrowserTransfer,
        destination: URL,
        conflict: FileBrowserConflictResolution,
        checkingConflicts: Bool
    ) {
        let urls = urls(in: transfer)
        let services = fileServices
        if checkingConflicts {
            guard !isPerformingOperation else { return }
            isPerformingOperation = true
            operationWorker.run({ services.conflictingDestinations(for: urls, in: destination) }) { [weak self] result in
                guard let self else { return }
                self.isPerformingOperation = false
                switch result {
                case let .success(conflicts) where !conflicts.isEmpty:
                    self.focusedConflictResolution = .keepBoth
                    self.focusState = .confirming(.conflict(transfer, destination: destination, conflicts: conflicts))
                case .success:
                    self.confirmTransfer(transfer, destination: destination, conflict: conflict, checkingConflicts: false)
                case let .failure(error):
                    self.statusMessage = error.localizedDescription
                }
            }
            return
        }

        performBlockingAction(recoveringTo: .confirming(.transfer(transfer, destination: destination)), operation: {
            switch transfer {
            case let .copy(urls):
                try services.copy(urls, to: destination, conflict: conflict)
            case let .move(urls):
                try services.move(urls, to: destination, conflict: conflict)
            }
        }) { model in
            model.selectedURLs = []
            model.focusState = .browse
            model.reloadEntries()
        }
    }

    private func moveConflictResolution(by delta: Int) {
        let options = FileBrowserConflictResolution.allCases
        guard let index = options.firstIndex(of: focusedConflictResolution) else {
            focusedConflictResolution = .keepBoth
            return
        }
        let nextIndex = max(0, min(options.count - 1, index + delta))
        focusedConflictResolution = options[nextIndex]
    }

    private func urls(in transfer: FileBrowserTransfer) -> [URL] {
        switch transfer {
        case let .copy(urls), let .move(urls):
            return urls
        }
    }

    private func performServiceAction(recoveringTo focusState: FileBrowserFocusState, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            statusMessage = error.localizedDescription
            self.focusState = focusState
        }
    }

    private func performBlockingAction(
        recoveringTo recovery: FileBrowserFocusState,
        operation: @escaping () throws -> Void,
        completion: @escaping (FileBrowserModel) -> Void
    ) {
        guard !isPerformingOperation else { return }
        isPerformingOperation = true
        operationWorker.run(operation) { [weak self] result in
            guard let self else { return }
            self.isPerformingOperation = false
            switch result {
            case .success: completion(self)
            case let .failure(error):
                self.statusMessage = error.localizedDescription
                self.focusState = recovery
            }
        }
    }

    private func reloadEntries(
        selecting preferredSelection: URL? = nil,
        fallbackToHomeOnFailure: Bool = false,
        statusAfterLoad: String? = nil
    ) {
        guard isActive else { return }
        snapshotEntryCache.removeAll()
        pendingSnapshotRequests.removeAll()
        directoryLoadGeneration += 1
        let generation = directoryLoadGeneration
        let requestedDirectory = currentDirectory
        isLoadingEntries = true
        entries = []
        directorySnapshots = [FileBrowserDirectorySnapshot(directory: requestedDirectory, entries: [])]

        directoryStream.loadEntries(in: requestedDirectory, sort: sort, foldersFirst: foldersFirst) { [weak self] result in
            guard let self, generation == self.directoryLoadGeneration else { return }

            switch result {
            case let .success(loadedEntries):
                self.applyLoadedEntries(loadedEntries, selecting: preferredSelection, status: statusAfterLoad)
            case let .failure(error):
                self.applyDirectoryLoadFailure(error, fallbackToHomeOnFailure: fallbackToHomeOnFailure)
            }
        }
    }

    private func applyDirectoryLoadFailure(_ error: Error, fallbackToHomeOnFailure: Bool) {
        if fallbackToHomeOnFailure {
            let fallback = fileSystem.homeDirectory()
            if fallback.standardizedFileURL.path != currentDirectory.standardizedFileURL.path {
                currentDirectory = fallback
                selectedIndex = 0
                selectionAnchor = nil
                observeCurrentDirectory()
                reloadEntries(fallbackToHomeOnFailure: false, statusAfterLoad: error.localizedDescription)
                return
            }
        }
        isLoadingEntries = false
        entries = []
        directorySnapshots = [FileBrowserDirectorySnapshot(directory: currentDirectory, entries: [])]
        statusMessage = error.localizedDescription
    }

    private func applyLoadedEntries(
        _ loadedEntries: [FileBrowserEntry],
        selecting preferredSelection: URL?,
        status: String? = nil
    ) {
        isLoadingEntries = false
        entries = loadedEntries
        snapshotEntryCache[cacheKey(for: currentDirectory)] = entries
        selectEntry(matching: preferredSelection)
        rememberCurrentDirectorySelection()
        statusMessage = status ?? store.persistenceError
        pruneStaleSelections()
        rebuildDirectorySnapshots(force: true)
        publishSelectionScrollEvent(anchor: .top)
        persist()
    }

    private func rebuildDirectorySnapshots(force: Bool = false) {
        let directories = snapshotDirectories()
        guard force || directories != directorySnapshots.map(\.directory) else { return }

        directorySnapshots = directories.map { directory in
            FileBrowserDirectorySnapshot(directory: directory, entries: snapshotEntries(in: directory))
        }
    }

    private func snapshotDirectories() -> [URL] {
        [currentDirectory]
    }

    private func snapshotEntries(in directory: URL) -> [FileBrowserEntry] {
        if directory == currentDirectory {
            return entries
        }

        let key = cacheKey(for: directory)
        if let cached = snapshotEntryCache[key] {
            return cached
        }

        guard !pendingSnapshotRequests.contains(key) else { return [] }

        pendingSnapshotRequests.insert(key)
        let generation = directoryLoadGeneration
        var hasReturned = false
        directoryStream.loadEntries(in: directory, sort: sort, foldersFirst: foldersFirst) { [weak self] result in
            guard let self, generation == self.directoryLoadGeneration else { return }
            let loaded = (try? result.get()) ?? []
            self.snapshotEntryCache[key] = loaded
            self.pendingSnapshotRequests.remove(key)
            if hasReturned {
                self.rebuildDirectorySnapshots(force: true)
            }
        }
        hasReturned = true
        return snapshotEntryCache[key] ?? []
    }

    private func cacheKey(for directory: URL) -> DirectorySnapshotCacheKey {
        DirectorySnapshotCacheKey(directory: directory.standardizedFileURL, sort: sort, foldersFirst: foldersFirst)
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        moveSelection(to: selectedIndex + delta, anchor: .nearest)
    }

    private func moveSelection(to index: Int, anchor: FileBrowserSelectionScrollAnchor = .nearest) {
        guard !entries.isEmpty else { return }
        selectedIndex = max(0, min(entries.count - 1, index))
        rebuildDirectorySnapshots()
        rememberCurrentDirectorySelection()
        publishSelectionScrollEvent(anchor: anchor)
        refreshQuickLookPreviewIfNeeded()
    }

    private func moveToParent() {
        guard let parent = fileSystem.parentURL(for: currentDirectory) else {
            publishWobble(.noParentDirectory)
            return
        }
        let child = currentDirectory
        rememberCurrentDirectorySelection()
        recentTraversalChain.insert(currentDirectory, at: 0)
        recentTraversalChain = Array(recentTraversalChain.prefix(FileBrowserRetentionPolicy.historyLimit))
        navigateToDirectory(
            URL(fileURLWithPath: parent.path),
            selecting: child,
            transition: .parent
        )
    }

    private func enterSelectedDirectoryOrWobble() {
        if let remembered = recentTraversalChain.first,
           let entry = selectedEntry,
           let targetDirectory = directoryURL(for: entry),
           targetDirectory.path == remembered.standardizedFileURL.path {
            recentTraversalChain.removeFirst()
            rememberCurrentDirectorySelection()
            navigateToDirectory(
                targetDirectory,
                selecting: recentTraversalChain.first ?? rememberedSelection(in: targetDirectory),
                transition: .deeper
            )
            return
        }

        guard let entry = selectedEntry,
              let child = directoryURL(for: entry) else {
            publishWobble(.cannotEnterFile)
            return
        }
        rememberCurrentDirectorySelection()
        navigateToDirectory(
            child,
            selecting: rememberedSelection(in: child),
            transition: .deeper
        )
    }

    private func directoryURL(for entry: FileBrowserEntry) -> URL? {
        switch entry.kind {
        case .directory, .symbolicLink, .other:
            return fileSystem.resolvedDirectoryURL(for: entry.url)
        case .file, .package:
            return nil
        }
    }

    private func prepareSpaceInteraction() {
        pendingSpaceInteractionURL = selectedEntry?.url
    }

    private func toggleSelection() {
        guard let url = pendingSpaceInteractionURL ?? selectedEntry?.url else { return }
        pendingSpaceInteractionURL = nil
        if selectedURLs.contains(url) {
            selectedURLs.removeAll { $0 == url }
        } else {
            selectedURLs.append(url)
        }
        selectionAnchor = entries.firstIndex { $0.url == url } ?? selectedIndex
    }

    private func rangeSelect() {
        guard !entries.isEmpty else { return }
        let anchor = max(0, min(entries.count - 1, selectionAnchor ?? selectedIndex))
        let bounds = min(anchor, selectedIndex)...max(anchor, selectedIndex)
        let urls = bounds.map { entries[$0].url }
        selectedURLs = selectedURLs + urls.filter { !selectedURLs.contains($0) }
    }

    private func cycle(toFirstCharacter character: Character, direction: FileBrowserCycleDirection) {
        guard !entries.isEmpty else { return }
        let needle = String(character).lowercased()
        let orderedIndexes: [Int]
        switch direction {
        case .forward:
            let start = min(selectedIndex + 1, entries.count)
            orderedIndexes = Array(start..<entries.count) + Array(0..<start)
        case .backward:
            let beforeSelection = selectedIndex > 0
                ? Array(stride(from: selectedIndex - 1, through: 0, by: -1))
                : []
            orderedIndexes = beforeSelection
                + Array(stride(from: entries.count - 1, through: selectedIndex, by: -1))
        }
        if let match = orderedIndexes.first(where: { entryMatchesFirstCharacter(entries[$0], needle: needle) }) {
            moveSelection(to: match)
        }
    }

    private func entryMatchesFirstCharacter(_ entry: FileBrowserEntry, needle: String) -> Bool {
        guard let firstSearchableCharacter = entry.name.first(where: { $0.isLetter || $0.isNumber }) else {
            return false
        }
        return String(firstSearchableCharacter).lowercased() == needle
    }

    private func pinMatchesFirstCharacter(_ url: URL, needle: String) -> Bool {
        guard let firstSearchableCharacter = url.lastPathComponent.first(where: { $0.isLetter || $0.isNumber }) else {
            return false
        }
        return String(firstSearchableCharacter).lowercased() == needle
    }

    private func moveFocusedPin(by delta: Int) {
        moveFocusedPin(to: focusedPinnedIndex + delta)
    }

    private func moveFocusedPin(to index: Int) {
        guard !sidebarDirectories.isEmpty else { return }
        focusedPinnedIndex = max(0, min(sidebarDirectories.count - 1, index))
    }

    private func cyclePinnedItems(toFirstCharacter character: Character, direction: FileBrowserCycleDirection) {
        let directories = sidebarDirectories
        guard !directories.isEmpty else { return }
        let needle = String(character).lowercased()
        let orderedIndexes: [Int]
        switch direction {
        case .forward:
            let start = min(focusedPinnedIndex + 1, directories.count)
            orderedIndexes = Array(start..<directories.count) + Array(0..<start)
        case .backward:
            let beforeSelection = focusedPinnedIndex > 0
                ? Array(stride(from: focusedPinnedIndex - 1, through: 0, by: -1))
                : []
            orderedIndexes = beforeSelection
                + Array(stride(from: directories.count - 1, through: focusedPinnedIndex, by: -1))
        }

        if let match = orderedIndexes.first(where: { pinMatchesFirstCharacter(directories[$0], needle: needle) }) {
            focusedPinnedIndex = match
        }
    }

    private func beginPinnedFocus() {
        guard !sidebarDirectories.isEmpty else { return }
        clampFocusedPinnedIndex()
        focusState = .pinnedItems
    }

    private func endPinnedFocus() {
        if focusState == .pinnedItems {
            focusState = .browse
        }
    }

    private func openFocusedPin() {
        guard let focusedPinnedURL else { return }
        openPinnedURL(focusedPinnedURL)
    }

    private func openPinnedURL(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let targetDirectory: URL
        let preferredSelection: URL?

        if let resolvedDirectory = fileSystem.resolvedDirectoryURL(for: standardizedURL) {
            targetDirectory = resolvedDirectory
            preferredSelection = rememberedSelection(in: resolvedDirectory)
        } else if let parent = fileSystem.parentURL(for: standardizedURL) {
            targetDirectory = parent.standardizedFileURL
            preferredSelection = standardizedURL
        } else {
            publishWobble(.noParentDirectory)
            return
        }

        focusState = .browse
        navigateToDirectory(
            targetDirectory,
            selecting: preferredSelection,
            transition: nil
        )
    }

    private func togglePinSelectedItem() {
        guard let url = selectedEntry?.url else { return }
        togglePin(url)
    }

    private func clampFocusedPinnedIndex() {
        guard !sidebarDirectories.isEmpty else {
            focusedPinnedIndex = 0
            return
        }
        focusedPinnedIndex = max(0, min(sidebarDirectories.count - 1, focusedPinnedIndex))
    }

    private func navigateToDirectory(
        _ directory: URL,
        selecting preferredSelection: URL?,
        transition: FileBrowserNavigationDirection?,
        recordHistory: Bool = true
    ) {
        rememberCurrentDirectorySelection()
        let standardizedDirectory = directory.standardizedFileURL
        let standardizedCurrent = currentDirectory.standardizedFileURL
        guard standardizedDirectory.path != standardizedCurrent.path else {
            reloadEntries(selecting: preferredSelection)
            return
        }

        if recordHistory {
            directoryBackStack.append(standardizedCurrent)
            directoryBackStack = Array(directoryBackStack.suffix(FileBrowserRetentionPolicy.historyLimit))
            directoryForwardStack.removeAll()
        }

        currentDirectory = standardizedDirectory
        selectedIndex = 0
        selectionAnchor = nil
        observeCurrentDirectory()
        if let transition {
            publishNavigationTransition(transition)
        }
        reloadEntries(selecting: preferredSelection)
    }

    private func moveDirectoryHistoryBack() {
        guard let previous = directoryBackStack.popLast() else { return }
        rememberCurrentDirectorySelection()
        directoryForwardStack.append(currentDirectory.standardizedFileURL)
        directoryForwardStack = Array(directoryForwardStack.suffix(FileBrowserRetentionPolicy.historyLimit))
        currentDirectory = previous.standardizedFileURL
        selectedIndex = 0
        selectionAnchor = nil
        focusState = .browse
        observeCurrentDirectory()
        reloadEntries(selecting: rememberedSelection(in: previous))
    }

    private func moveDirectoryHistoryForward() {
        guard let next = directoryForwardStack.popLast() else { return }
        rememberCurrentDirectorySelection()
        directoryBackStack.append(currentDirectory.standardizedFileURL)
        directoryBackStack = Array(directoryBackStack.suffix(FileBrowserRetentionPolicy.historyLimit))
        currentDirectory = next.standardizedFileURL
        selectedIndex = 0
        selectionAnchor = nil
        focusState = .browse
        observeCurrentDirectory()
        reloadEntries(selecting: rememberedSelection(in: next))
    }

    private func observeCurrentDirectory() {
        guard isActive else { return }
        let standardizedDirectory = currentDirectory.standardizedFileURL
        guard observedDirectory?.path != standardizedDirectory.path else { return }

        directoryObservation?.cancel()
        observedDirectory = standardizedDirectory
        directoryObservation = directoryObserver?.observe(directory: standardizedDirectory) { [weak self] in
            self?.scheduleObservedDirectoryRefresh()
        }
    }

    private func scheduleObservedDirectoryRefresh() {
        guard isActive else { return }
        observationRefreshTask?.cancel()
        observationRefreshTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) }
            catch { return }
            guard let self, self.isActive else { return }
            self.reloadObservedDirectory()
        }
    }

    private func reloadObservedDirectory() {
        guard isActive, !isPerformingOperation else { return }
        guard observedDirectory?.path == currentDirectory.standardizedFileURL.path else { return }
        let preferredSelection = selectedEntry?.url ?? rememberedSelection(in: currentDirectory)
        reloadEntries(selecting: preferredSelection)
    }

    private func selectEntry(matching preferredSelection: URL?) {
        if let preferredSelection,
           let index = entries.firstIndex(where: { $0.url.standardizedFileURL.path == preferredSelection.standardizedFileURL.path }) {
            selectedIndex = index
        } else {
            selectedIndex = entries.isEmpty ? 0 : min(selectedIndex, entries.count - 1)
        }
    }

    private func rememberCurrentDirectorySelection() {
        guard let url = selectedEntry?.url else { return }
        rememberedSelectionByDirectory[currentDirectory.standardizedFileURL] = url.standardizedFileURL
        rememberedDirectoryOrder.removeAll { $0 == currentDirectory.standardizedFileURL }
        rememberedDirectoryOrder.append(currentDirectory.standardizedFileURL)
        if rememberedDirectoryOrder.count > FileBrowserRetentionPolicy.selectionLimit {
            let removed = rememberedDirectoryOrder.removeFirst()
            rememberedSelectionByDirectory.removeValue(forKey: removed)
        }
    }

    private func rememberedSelection(in directory: URL) -> URL? {
        rememberedSelectionByDirectory[directory.standardizedFileURL]
    }

    private func publishWobble(_ reason: FileBrowserWobbleReason) {
        wobbleReason = reason
        nextWobbleID += 1
        wobbleEvent = FileBrowserWobbleEvent(id: nextWobbleID, reason: reason)
    }

    private func publishNavigationTransition(_ direction: FileBrowserNavigationDirection) {
        nextNavigationTransitionID += 1
        navigationTransition = FileBrowserNavigationTransition(id: nextNavigationTransitionID, direction: direction)
    }

    private func publishSelectionScrollEvent(anchor: FileBrowserSelectionScrollAnchor) {
        guard let url = selectedEntry?.url else { return }
        nextSelectionScrollID += 1
        selectionScrollEvent = FileBrowserSelectionScrollEvent(id: nextSelectionScrollID, url: url, anchor: anchor)
    }

    private func beginQuickLook() {
        guard let url = pendingSpaceInteractionURL ?? selectedEntry?.url else { return }
        focusState = .quickLook(preview(for: url))
    }

    private func refreshQuickLookPreviewIfNeeded() {
        guard case .quickLook = focusState,
              let url = selectedEntry?.url else {
            return
        }
        focusState = .quickLook(preview(for: url))
    }

    private func preview(for url: URL) -> FileBrowserPreview {
        FileBrowserPreview(
            url: url,
            mode: fileServices.previewMode(for: url)
        )
    }

    private func endQuickLook() {
        pendingSpaceInteractionURL = nil
        if case .quickLook = focusState {
            focusState = .browse
        }
    }

    private func closeFocusedState() {
        pendingSpaceInteractionURL = nil
        switch focusState {
        case .quickLook:
            focusState = .browse
        case .pinnedItems:
            focusState = .browse
        case .renaming:
            renameState = nil
            focusState = .previewActions
        case .transferPending:
            focusState = .previewActions
        case .confirming(.transfer), .confirming(.conflict), .confirming(.unmount):
            focusState = .previewActions
        case .confirming(.trash):
            focusState = .previewActions
        default:
            focusState = .browse
        }
    }

    private func pruneStaleSelections() {
        let validURLs = Set(entries.map(\.url))
        let currentPath = currentDirectory.standardizedFileURL.path
        selectedURLs.removeAll {
            !validURLs.contains($0) && $0.deletingLastPathComponent().standardizedFileURL.path == currentPath
        }
    }

    private func persist() {
        store.update(FileBrowserPersistedState(
            pinnedDirectories: pinnedDirectories,
            lastDirectory: currentDirectory,
            sort: sort,
            foldersFirst: foldersFirst,
            traversalChain: recentTraversalChain,
            rememberedSelections: rememberedDirectoryOrder
                .compactMap { directory in
                    rememberedSelectionByDirectory[directory].map {
                        FileBrowserRememberedSelection(directory: directory, selection: $0)
                    }
                },
            directoryBookmarks: store.state.directoryBookmarks
        ), remembering: currentDirectory)
    }
}

private enum FileBrowserCycleDirection {
    case forward
    case backward
}

#if DEBUG
extension FileBrowserModel {
    func replaceEntriesForTesting(_ nextEntries: [FileBrowserEntry]) {
        entries = nextEntries
        pruneStaleSelections()
    }

    func addSelectedURLForTesting(_ url: URL) {
        selectedURLs.append(url)
    }
}
#endif

private struct DirectorySnapshotCacheKey: Hashable {
    let directory: URL
    let sort: FileBrowserSort
    let foldersFirst: Bool
}
