import AppKit
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
    var rememberedSelections: [FileBrowserRememberedSelection]

    static let defaultValue = FileBrowserPersistedState(
        pinnedDirectories: [],
        lastDirectory: nil,
        sort: .name,
        traversalChain: [],
        rememberedSelections: []
    )

    init(
        pinnedDirectories: [URL],
        lastDirectory: URL?,
        sort: FileBrowserSort,
        traversalChain: [URL],
        rememberedSelections: [FileBrowserRememberedSelection] = []
    ) {
        self.pinnedDirectories = pinnedDirectories
        self.lastDirectory = lastDirectory
        self.sort = sort
        self.traversalChain = traversalChain
        self.rememberedSelections = rememberedSelections
    }

    private enum CodingKeys: String, CodingKey {
        case pinnedDirectories
        case lastDirectory
        case sort
        case traversalChain
        case rememberedSelections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinnedDirectories = try container.decodeIfPresent([URL].self, forKey: .pinnedDirectories) ?? []
        lastDirectory = try container.decodeIfPresent(URL.self, forKey: .lastDirectory)
        sort = try container.decodeIfPresent(FileBrowserSort.self, forKey: .sort) ?? .name
        traversalChain = try container.decodeIfPresent([URL].self, forKey: .traversalChain) ?? []
        rememberedSelections = try container.decodeIfPresent(
            [FileBrowserRememberedSelection].self,
            forKey: .rememberedSelections
        ) ?? []
    }
}

struct FileBrowserRememberedSelection: Codable, Equatable {
    let directory: URL
    let selection: URL
}

struct FileBrowserDirectorySnapshot: Equatable {
    let directory: URL
    let entries: [FileBrowserEntry]
}

struct FileBrowserConflict: Equatable {
    let source: URL
    let destination: URL
}

enum FileBrowserPreviewMode: Equatable {
    case nativeThumbnail
    case metadataFallback
}

struct FileBrowserPreview: Equatable {
    let url: URL
    let mode: FileBrowserPreviewMode
}

protocol FileSystemClientProtocol {
    func homeDirectory() -> URL
    func parentURL(for url: URL) -> URL?
    func isDirectory(_ url: URL) -> Bool
    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry]
}

extension FileSystemClient: FileSystemClientProtocol {}

protocol FileBrowserPersisting: AnyObject {
    var state: FileBrowserPersistedState { get }
    func update(_ nextState: FileBrowserPersistedState)
}

extension FileBrowserStore: FileBrowserPersisting {}

protocol FileBrowserNativeServicing {
    func open(_ url: URL) throws
    func revealInFinder(_ urls: [URL]) throws
    func copyPathsToPasteboard(_ urls: [URL]) throws
    func icon(for url: URL) -> NSImage
    func copy(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws
    func move(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws
    func trash(_ urls: [URL]) throws
    func rename(_ url: URL, to proposedName: String) throws -> URL
    func batchRename(_ urls: [URL], baseName: String) throws -> [URL]
    func conflictingDestinations(for urls: [URL], in destinationDirectory: URL) -> [FileBrowserConflict]
    func previewMode(for url: URL) -> FileBrowserPreviewMode
    func loadPreviewThumbnail(
        for url: URL,
        size: CGSize,
        scale: CGFloat,
        completion: @escaping (NSImage?) -> Void
    )
}

enum FileBrowserFocusState: Equatable {
    case browse
    case pinnedItems
    case previewActions
    case renaming
    case transferPending(FileBrowserTransfer)
    case confirming(FileBrowserConfirmation)
    case quickLook(FileBrowserPreview)
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

enum FileBrowserConflictResolution: CaseIterable, Equatable {
    case keepBoth
    case replace
    case cancel
}

enum FileBrowserRenameMode: Equatable {
    case single
    case batch
}

struct FileBrowserRenameState: Equatable {
    let mode: FileBrowserRenameMode
    let urls: [URL]
    var proposedName: String
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
    case conflict(FileBrowserTransfer, destination: URL, conflicts: [FileBrowserConflict])
}

enum FileBrowserWobbleReason: Equatable {
    case cannotEnterFile
    case noParentDirectory
}

struct FileBrowserWobbleEvent: Equatable {
    let id: Int
    let reason: FileBrowserWobbleReason
}

enum FileBrowserNavigationDirection: Equatable {
    case deeper
    case parent
}

struct FileBrowserNavigationTransition: Equatable {
    let id: Int
    let direction: FileBrowserNavigationDirection
}

enum FileBrowserSelectionScrollAnchor: Equatable {
    case nearest
    case top
    case bottom
}

struct FileBrowserSelectionScrollEvent: Equatable {
    let id: Int
    let url: URL
    let anchor: FileBrowserSelectionScrollAnchor
}

struct FileBrowserMotionPolicy {
    static let wobbleAmplitude = 1.6
    static let wobbleOscillations = 1.0
    static let listReconstructionAnimationSeconds = 0.18
}
