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

struct FileBrowserDirectorySnapshot: Equatable {
    let directory: URL
    let entries: [FileBrowserEntry]
}
