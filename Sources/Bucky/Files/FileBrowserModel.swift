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

    private let fileSystem: FileSystemClientProtocol
    private let store: FileBrowserPersisting
    private var selectionAnchor: Int?
    private var recentTraversalChain: [URL]

    var selectedEntry: FileBrowserEntry? {
        guard selectedIndex >= 0, selectedIndex < entries.count else { return nil }
        return entries[selectedIndex]
    }

    init(fileSystem: FileSystemClientProtocol = FileSystemClient(), store: FileBrowserPersisting = FileBrowserStore()) {
        self.fileSystem = fileSystem
        self.store = store
        self.sort = store.state.sort
        self.recentTraversalChain = store.state.traversalChain
        self.currentDirectory = store.state.lastDirectory ?? fileSystem.homeDirectory()
        reloadEntries()
    }

    func handle(_ command: LauncherCommand) {
        switch command {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
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
            focusState = .previewActions
        case .close:
            closeFocusedState()
        default:
            break
        }
    }

    private func reloadEntries() {
        do {
            entries = try fileSystem.entries(in: currentDirectory, sort: sort)
            selectedIndex = entries.isEmpty ? 0 : min(selectedIndex, entries.count - 1)
            pruneStaleSelections()
            persist()
        } catch {
            entries = []
        }
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = max(0, min(entries.count - 1, selectedIndex + delta))
    }

    private func moveToParent() {
        guard let parent = fileSystem.parentURL(for: currentDirectory) else {
            wobbleReason = .noParentDirectory
            return
        }
        recentTraversalChain.insert(currentDirectory, at: 0)
        currentDirectory = parent
        selectedIndex = 0
        selectionAnchor = nil
        reloadEntries()
    }

    private func enterSelectedDirectoryOrWobble() {
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
            selectedIndex = match
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
        focusState = .browse
    }

    private func pruneStaleSelections() {
        let validURLs = Set(entries.map(\.url))
        selectedURLs.removeAll { !validURLs.contains($0) }
    }

    private func persist() {
        store.update(FileBrowserPersistedState(
            pinnedDirectories: store.state.pinnedDirectories,
            lastDirectory: currentDirectory,
            sort: sort,
            traversalChain: recentTraversalChain
        ))
    }
}
