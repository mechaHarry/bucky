import Foundation

struct FileBrowserEntry: Identifiable, Hashable {
    enum Kind: String, Codable, Hashable {
        case file
        case directory
        case package
        case symbolicLink
        case other
    }

    let id: URL
    let url: URL
    let name: String
    let kind: Kind
    let size: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let isHidden: Bool

    init(
        url: URL,
        kind: Kind,
        size: Int64?,
        createdAt: Date?,
        modifiedAt: Date?,
        isHidden: Bool
    ) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isHidden = isHidden
    }
}

enum FileBrowserSort: String, Codable, CaseIterable, Hashable {
    case name
    case dateCreated
    case dateModified
    case size
}

struct FileBrowserPersistedState: Codable, Equatable {
    var pinnedDirectories: [URL]
    var lastDirectory: URL?
    var sort: FileBrowserSort
    var traversalChain: [URL]

    static let defaultValue = FileBrowserPersistedState(
        pinnedDirectories: [],
        lastDirectory: nil,
        sort: .name,
        traversalChain: []
    )
}

struct FileBrowserDirectorySnapshot: Equatable {
    let directory: URL
    let entries: [FileBrowserEntry]
}

protocol FileSystemClientProtocol {
    func homeDirectory() -> URL
    func parentURL(for url: URL) -> URL?
    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry]
}

extension FileSystemClient: FileSystemClientProtocol {}

protocol FileBrowserPersisting: AnyObject {
    var state: FileBrowserPersistedState { get }
    func update(_ nextState: FileBrowserPersistedState)
}

extension FileBrowserStore: FileBrowserPersisting {}

enum FileBrowserFocusState: Equatable {
    case browse
    case previewActions
    case renaming
    case transferPending(FileBrowserTransfer)
    case confirming(FileBrowserConfirmation)
    case quickLook(URL)
}

enum FileBrowserAction: String, CaseIterable, Equatable {
    case open
    case rename
    case batchRename
    case revealInFinder
    case copyPath
    case copyPaths
    case copy
    case move
    case moveToTrash
}

enum FileBrowserActionIntent: Equatable {
    case open(URL)
    case rename([URL])
    case revealInFinder([URL])
    case copyPaths([URL])
}

enum FileBrowserTransferKind {
    case copy
    case move
}

enum FileBrowserTransfer: Equatable {
    case copy([URL])
    case move([URL])
}

enum FileBrowserConfirmation: Equatable {
    case transfer(FileBrowserTransfer, destination: URL)
    case trash([URL], step: Int)
    case conflict(source: URL, destination: URL)
}

enum FileBrowserWobbleReason: Equatable {
    case cannotEnterFile
    case noParentDirectory
}
