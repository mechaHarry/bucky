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
    var directoryBookmarks: [FileBrowserDirectoryBookmark]

    static let defaultValue = FileBrowserPersistedState(
        pinnedDirectories: [],
        lastDirectory: nil,
        sort: .name,
        traversalChain: [],
        rememberedSelections: [],
        directoryBookmarks: []
    )

    init(
        pinnedDirectories: [URL],
        lastDirectory: URL?,
        sort: FileBrowserSort,
        traversalChain: [URL],
        rememberedSelections: [FileBrowserRememberedSelection] = [],
        directoryBookmarks: [FileBrowserDirectoryBookmark] = []
    ) {
        self.pinnedDirectories = pinnedDirectories
        self.lastDirectory = lastDirectory
        self.sort = sort
        self.traversalChain = traversalChain
        self.rememberedSelections = rememberedSelections
        self.directoryBookmarks = directoryBookmarks
    }

    private enum CodingKeys: String, CodingKey {
        case pinnedDirectories
        case lastDirectory
        case sort
        case traversalChain
        case rememberedSelections
        case directoryBookmarks
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
        directoryBookmarks = try container.decodeIfPresent(
            [FileBrowserDirectoryBookmark].self,
            forKey: .directoryBookmarks
        ) ?? []
    }
}

struct FileBrowserRememberedSelection: Codable, Equatable {
    let directory: URL
    let selection: URL
}

struct FileBrowserDirectoryBookmark: Codable, Equatable {
    let directory: URL
    let bookmarkData: Data
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
    case video
    case codeText
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
    func resolvedDirectoryURL(for url: URL) -> URL?
    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry]
}

extension FileSystemClient: FileSystemClientProtocol {}

protocol FileBrowserPersisting: AnyObject {
    var state: FileBrowserPersistedState { get }
    func update(_ nextState: FileBrowserPersistedState)
    func bookmarkData(for directory: URL) -> Data?
    func rememberDirectoryAccess(_ directory: URL)
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

struct FileBrowserPreviewLayoutPolicy {
    static let surfaceMargin: CGFloat = 16
    static let surfacePadding: CGFloat = 24
    static let previewTextStackHeight: CGFloat = 62

    static func surfaceSize(for mode: FileBrowserPreviewMode, availableSize: CGSize) -> CGSize {
        let maxWidth = max(0, availableSize.width - surfaceMargin * 2)
        let maxHeight = max(0, availableSize.height)
        let targetHeight = maxHeight
        let targetWidth = min(maxWidth, max(minimumSurfaceSize(for: mode).width, targetHeight * preferredAspectRatio(for: mode)))

        return CGSize(
            width: targetWidth.rounded(.down),
            height: targetHeight.rounded(.down)
        )
    }

    static func contentSize(surfaceSize: CGSize) -> CGSize {
        CGSize(
            width: max(0, surfaceSize.width - surfacePadding * 2),
            height: max(0, surfaceSize.height - surfacePadding * 2)
        )
    }

    static func contentSize(for mode: FileBrowserPreviewMode) -> CGSize {
        switch mode {
        case .metadataFallback:
            return CGSize(width: 360, height: 250)
        case .nativeThumbnail:
            return CGSize(width: 560, height: 380)
        case .video:
            return CGSize(width: 720, height: 450)
        case .codeText:
            return CGSize(width: 720, height: 480)
        }
    }

    static func previewAreaHeight(for mode: FileBrowserPreviewMode, contentSize: CGSize) -> CGFloat {
        switch mode {
        case .metadataFallback:
            return min(128, max(86, contentSize.height * 0.28))
        case .nativeThumbnail:
            return contentSize.height
        case .video, .codeText:
            return max(160, contentSize.height - previewTextStackHeight)
        }
    }

    static func overlaysMetadata(for mode: FileBrowserPreviewMode) -> Bool {
        mode == .nativeThumbnail
    }

    static func previewAreaHeight(for mode: FileBrowserPreviewMode) -> CGFloat {
        switch mode {
        case .metadataFallback:
            return 86
        case .nativeThumbnail:
            return 260
        case .video:
            return 336
        case .codeText:
            return 366
        }
    }

    private static func minimumSurfaceSize(for mode: FileBrowserPreviewMode) -> CGSize {
        switch mode {
        case .metadataFallback:
            return CGSize(width: 360, height: 250)
        case .nativeThumbnail:
            return CGSize(width: 640, height: 460)
        case .video, .codeText:
            return CGSize(width: 720, height: 480)
        }
    }

    private static func preferredAspectRatio(for mode: FileBrowserPreviewMode) -> CGFloat {
        switch mode {
        case .metadataFallback:
            return 0.80
        case .nativeThumbnail:
            return 1.25
        case .video:
            return 16.0 / 9.0
        case .codeText:
            return 1.45
        }
    }
}

struct FileBrowserRowFocusIndicatorPolicy {
    static let activeIndicatorWidth: CGFloat = 3
    static let activeIndicatorHeight: CGFloat = 24
    static let activeSelectionOpacity = 0.24
    static let markedSelectionOpacity = 0.12
}

struct FileBrowserActionPaneLayoutPolicy {
    static let width: CGFloat = 268
    static let padding: CGFloat = 14
    static let cardStackHeight: CGFloat = 58
    static let selectionRowHeight: CGFloat = 18
    static let maximumVisibleSelectionRows = 4

    static var contentWidth: CGFloat {
        width - padding * 2
    }

    static func usesCardStack(selectionCount: Int) -> Bool {
        selectionCount > 1
    }
}

struct FileBrowserActionPaneSelectionRows: Equatable {
    let visible: [URL]
    let remainingCount: Int
}

struct FileBrowserActionPaneSelectionPolicy {
    static func rows(
        for urls: [URL],
        maximumVisibleRows: Int = FileBrowserActionPaneLayoutPolicy.maximumVisibleSelectionRows
    ) -> FileBrowserActionPaneSelectionRows {
        let visible = Array(urls.prefix(maximumVisibleRows))
        return FileBrowserActionPaneSelectionRows(
            visible: visible,
            remainingCount: max(0, urls.count - visible.count)
        )
    }
}

struct FileBrowserCodePreviewTheme {
    static let background = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)
    static let foreground = NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.96, alpha: 1)
    static let secondaryForeground = NSColor(calibratedRed: 0.56, green: 0.61, blue: 0.68, alpha: 1)
}

struct FileBrowserDragPolicy {
    static let nativeDragThreshold: CGFloat = 3
    static let mouseDownCanMoveWindow = false
    static let maximumDraggingImageSide: CGFloat = 48

    static func draggedURL(for url: URL) -> URL {
        url
    }

    static func shouldBeginNativeDrag(delta: CGSize) -> Bool {
        hypot(delta.width, delta.height) >= nativeDragThreshold
    }

    static func draggingImageFrame(
        in bounds: CGRect,
        iconSize: CGSize,
        pointerLocation: CGPoint
    ) -> CGRect {
        let imageSize = draggingImageSize(for: iconSize)
        let origin = CGPoint(
            x: pointerLocation.x - imageSize.width / 2,
            y: pointerLocation.y - imageSize.height / 2
        )
        return CGRect(origin: origin, size: imageSize)
    }

    static func itemProvider(for url: URL) -> NSItemProvider {
        NSItemProvider(contentsOf: draggedURL(for: url)) ?? NSItemProvider(object: draggedURL(for: url) as NSURL)
    }

    private static func draggingImageSize(for iconSize: CGSize) -> CGSize {
        guard iconSize.width > 0, iconSize.height > 0 else {
            return CGSize(width: maximumDraggingImageSide, height: maximumDraggingImageSide)
        }

        let scale = min(
            maximumDraggingImageSide / iconSize.width,
            maximumDraggingImageSide / iconSize.height,
            1
        )
        return CGSize(
            width: (iconSize.width * scale).rounded(.down),
            height: (iconSize.height * scale).rounded(.down)
        )
    }
}

struct FileBrowserIconPolicy {
    static func systemSymbolOverride(for url: URL) -> String? {
        url.lastPathComponent == ".Trash" ? "trash" : nil
    }
}
