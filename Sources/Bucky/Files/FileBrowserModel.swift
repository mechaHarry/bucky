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
    @Published private(set) var sort: FileBrowserSort
    @Published private(set) var pinnedDirectories: [URL] = []
    @Published private(set) var focusedActionIndex = 0
    @Published private(set) var directorySnapshots: [FileBrowserDirectorySnapshot] = []
    @Published private(set) var pendingActionIntent: FileBrowserActionIntent?

    private let fileSystem: FileSystemClientProtocol
    private let store: FileBrowserPersisting
    private var selectionAnchor: Int?
    private var recentTraversalChain: [URL]
    private var snapshotEntryCache: [DirectorySnapshotCacheKey: [FileBrowserEntry]] = [:]

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

    var availableActions: [FileBrowserAction] {
        activeSelectionURLs.count > 1
            ? [.batchRename, .copyPaths, .copy, .move, .moveToTrash]
            : [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash]
    }

    var focusableActions: [FileBrowserAction] {
        availableActions
    }

    init(fileSystem: FileSystemClientProtocol = FileSystemClient(), store: FileBrowserPersisting = FileBrowserStore()) {
        self.fileSystem = fileSystem
        self.store = store
        self.sort = store.state.sort
        self.pinnedDirectories = store.state.pinnedDirectories
        self.recentTraversalChain = store.state.traversalChain
        self.currentDirectory = store.state.lastDirectory ?? fileSystem.homeDirectory()
        reloadEntries()
    }

    func handle(_ command: LauncherCommand) {
        switch command {
        case .up:
            if focusState == .previewActions {
                moveFocusedAction(by: -1)
            } else {
                moveSelection(by: -1)
            }
        case .down:
            if focusState == .previewActions {
                moveFocusedAction(by: 1)
            } else {
                moveSelection(by: 1)
            }
        case .top:
            moveSelection(to: 0)
        case .bottom:
            moveSelection(to: entries.count - 1)
        case .left:
            moveToParent()
        case .right:
            enterSelectedDirectoryOrWobble()
        case .space:
            toggleSelection()
        case .shiftSpace:
            rangeSelect()
        case let .alphaNumeric(character):
            cycle(toFirstCharacter: character)
        case .beginSpaceHold:
            beginQuickLook()
        case .endSpaceHold:
            endQuickLook()
        case .open:
            if focusState == .previewActions {
                performFocusedAction()
            } else if case let .transferPending(transfer) = focusState {
                focusState = .confirming(.transfer(transfer, destination: currentDirectory))
            } else {
                focusedActionIndex = 0
                focusState = .previewActions
            }
        case .close:
            closeFocusedState()
        default:
            break
        }
    }

    func startTransfer(_ kind: FileBrowserTransferKind) {
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
        if pinnedDirectories.contains(url) {
            pinnedDirectories.removeAll { $0 == url }
        } else {
            pinnedDirectories.append(url)
        }
        persist()
    }

    func setSort(_ nextSort: FileBrowserSort) {
        guard sort != nextSort else { return }
        sort = nextSort
        reloadEntries()
    }

    func entry(for url: URL) -> FileBrowserEntry? {
        let standardizedURL = url.standardizedFileURL
        return directorySnapshots
            .lazy
            .flatMap(\.entries)
            .first { $0.url.standardizedFileURL == standardizedURL }
    }

    func performFocusedAction() {
        guard focusState == .previewActions else { return }
        let actions = focusableActions
        guard !actions.isEmpty else { return }
        let action = actions[max(0, min(actions.count - 1, focusedActionIndex))]
        pendingActionIntent = nil
        switch action {
        case .open:
            if let url = activeSelectionURLs.first {
                pendingActionIntent = .open(url)
            }
            focusState = .previewActions
        case .rename, .batchRename:
            pendingActionIntent = .rename(activeSelectionURLs)
            focusState = .renaming
        case .revealInFinder:
            pendingActionIntent = .revealInFinder(activeSelectionURLs)
            focusState = .previewActions
        case .copyPath, .copyPaths:
            pendingActionIntent = .copyPaths(activeSelectionURLs)
            focusState = .previewActions
        case .copy:
            startTransfer(.copy)
        case .move:
            startTransfer(.move)
        case .moveToTrash:
            requestTrashConfirmation()
        }
    }

    func moveFocusedAction(by delta: Int) {
        guard focusState == .previewActions, !focusableActions.isEmpty else { return }
        focusedActionIndex = max(0, min(focusableActions.count - 1, focusedActionIndex + delta))
    }

    private func reloadEntries() {
        snapshotEntryCache.removeAll()
        do {
            entries = try fileSystem.entries(in: currentDirectory, sort: sort)
            snapshotEntryCache[cacheKey(for: currentDirectory)] = entries
            selectedIndex = entries.isEmpty ? 0 : min(selectedIndex, entries.count - 1)
            pruneStaleSelections()
            rebuildDirectorySnapshots(force: true)
            persist()
        } catch {
            entries = []
            directorySnapshots = [FileBrowserDirectorySnapshot(directory: currentDirectory, entries: [])]
        }
    }

    private func rebuildDirectorySnapshots(force: Bool = false) {
        let directories = snapshotDirectories()
        guard force || directories != directorySnapshots.map(\.directory) else { return }

        directorySnapshots = directories.map { directory in
            FileBrowserDirectorySnapshot(directory: directory, entries: snapshotEntries(in: directory))
        }
    }

    private func snapshotDirectories() -> [URL] {
        var directories: [URL] = []

        if let parent = fileSystem.parentURL(for: currentDirectory) {
            directories.append(parent)
        }

        directories.append(currentDirectory)

        if let selectedEntry, selectedEntry.kind == .directory {
            directories.append(selectedEntry.url)
        }

        return directories
    }

    private func snapshotEntries(in directory: URL) -> [FileBrowserEntry] {
        if directory == currentDirectory {
            return entries
        }

        let key = cacheKey(for: directory)
        if let cached = snapshotEntryCache[key] {
            return cached
        }

        let loaded = (try? fileSystem.entries(in: directory, sort: sort)) ?? []
        snapshotEntryCache[key] = loaded
        return loaded
    }

    private func cacheKey(for directory: URL) -> DirectorySnapshotCacheKey {
        DirectorySnapshotCacheKey(directory: directory.standardizedFileURL, sort: sort)
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        moveSelection(to: selectedIndex + delta)
    }

    private func moveSelection(to index: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = max(0, min(entries.count - 1, index))
        rebuildDirectorySnapshots()
    }

    private func moveToParent() {
        guard let parent = fileSystem.parentURL(for: currentDirectory) else {
            wobbleReason = .noParentDirectory
            return
        }
        recentTraversalChain.insert(currentDirectory, at: 0)
        currentDirectory = URL(fileURLWithPath: parent.path)
        selectedIndex = 0
        selectionAnchor = nil
        reloadEntries()
    }

    private func enterSelectedDirectoryOrWobble() {
        if let remembered = recentTraversalChain.first,
           let entry = selectedEntry,
           entry.url.path == remembered.path,
           entry.kind == .directory {
            recentTraversalChain.removeFirst()
            currentDirectory = remembered
            selectedIndex = 0
            selectionAnchor = nil
            reloadEntries()
            return
        }

        guard let entry = selectedEntry, entry.kind == .directory else {
            wobbleReason = .cannotEnterFile
            return
        }
        currentDirectory = entry.url
        selectedIndex = 0
        selectionAnchor = nil
        reloadEntries()
    }

    private func toggleSelection() {
        guard let url = selectedEntry?.url else { return }
        if selectedURLs.contains(url) {
            selectedURLs.removeAll { $0 == url }
        } else {
            selectedURLs.append(url)
        }
        selectionAnchor = selectedIndex
    }

    private func rangeSelect() {
        guard !entries.isEmpty else { return }
        let anchor = max(0, min(entries.count - 1, selectionAnchor ?? selectedIndex))
        let bounds = min(anchor, selectedIndex)...max(anchor, selectedIndex)
        let urls = bounds.map { entries[$0].url }
        selectedURLs = selectedURLs + urls.filter { !selectedURLs.contains($0) }
    }

    private func cycle(toFirstCharacter character: Character) {
        guard !entries.isEmpty else { return }
        let needle = String(character).lowercased()
        let start = min(selectedIndex + 1, entries.count)
        let orderedIndexes = Array(start..<entries.count) + Array(0..<start)
        if let match = orderedIndexes.first(where: { entries[$0].name.lowercased().hasPrefix(needle) }) {
            moveSelection(to: match)
        }
    }

    private func beginQuickLook() {
        guard let url = selectedEntry?.url else { return }
        focusState = .quickLook(url)
    }

    private func endQuickLook() {
        if case .quickLook = focusState {
            focusState = .browse
        }
    }

    private func closeFocusedState() {
        switch focusState {
        case .transferPending:
            focusState = .previewActions
        default:
            focusState = .browse
        }
    }

    private func pruneStaleSelections() {
        let validURLs = Set(entries.map(\.url))
        selectedURLs.removeAll { !validURLs.contains($0) }
    }

    private func persist() {
        store.update(FileBrowserPersistedState(
            pinnedDirectories: pinnedDirectories,
            lastDirectory: currentDirectory,
            sort: sort,
            traversalChain: recentTraversalChain
        ))
    }
}

private struct DirectorySnapshotCacheKey: Hashable {
    let directory: URL
    let sort: FileBrowserSort
}
