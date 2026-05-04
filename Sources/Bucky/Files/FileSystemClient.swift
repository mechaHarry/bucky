import Foundation

struct FileSystemClient {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func homeDirectory() -> URL {
        fileManager.homeDirectoryForCurrentUser
    }

    func parentURL(for url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        guard parent.path != standardized.path else { return nil }
        return parent
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        let entries = try urls
            .map { url in
                let values = try url.resourceValues(forKeys: resourceKeys)
                return FileBrowserEntry(
                    url: url.standardizedFileURL,
                    kind: kind(for: values),
                    size: values.fileSize.map(Int64.init),
                    createdAt: values.creationDate,
                    modifiedAt: values.contentModificationDate,
                    isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix(".")
                )
            }
        return Self.sorted(entries, by: sort)
    }

    static func sorted(_ entries: [FileBrowserEntry], by sort: FileBrowserSort) -> [FileBrowserEntry] {
        entries.sorted { lhs, rhs in
            compare(lhs, rhs, sort: sort)
        }
    }

    private func kind(for values: URLResourceValues) -> FileBrowserEntry.Kind {
        if values.isSymbolicLink == true {
            return .symbolicLink
        }
        if values.isPackage == true {
            return .package
        }
        if values.isDirectory == true {
            return .directory
        }
        return .file
    }

    private static func compare(_ lhs: FileBrowserEntry, _ rhs: FileBrowserEntry, sort: FileBrowserSort) -> Bool {
        if lhs.kind == .directory, rhs.kind != .directory { return true }
        if lhs.kind != .directory, rhs.kind == .directory { return false }

        switch sort {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .dateCreated:
            return date(lhs.createdAt, isOrderedBefore: rhs.createdAt, fallbackLeft: lhs.name, fallbackRight: rhs.name)
        case .dateModified:
            return date(lhs.modifiedAt, isOrderedBefore: rhs.modifiedAt, fallbackLeft: lhs.name, fallbackRight: rhs.name)
        case .size:
            if (lhs.size ?? -1) == (rhs.size ?? -1) {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return (lhs.size ?? -1) > (rhs.size ?? -1)
        }
    }

    private static func date(_ lhs: Date?, isOrderedBefore rhs: Date?, fallbackLeft: String, fallbackRight: String) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return fallbackLeft.localizedStandardCompare(fallbackRight) == .orderedAscending
        }
    }
}
