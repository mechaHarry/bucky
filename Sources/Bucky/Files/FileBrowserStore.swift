import Foundation

final class FileBrowserStore {
    private let fileManager: FileManager
    private(set) var state: FileBrowserPersistedState
    let fileURL: URL

    init(
        fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("file-browser.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.state = .defaultValue
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            state = .defaultValue
            return
        }

        do {
            state = try JSONDecoder().decode(FileBrowserPersistedState.self, from: data)
        } catch {
            NSLog("Bucky could not read file browser state at %@: %@", fileURL.path, error.localizedDescription)
            state = .defaultValue
        }
    }

    func update(_ nextState: FileBrowserPersistedState) {
        state = nextState
        save()
    }

    func bookmarkData(for directory: URL) -> Data? {
        let standardizedDirectory = directory.standardizedFileURL
        return state.directoryBookmarks.first {
            $0.directory.standardizedFileURL.path == standardizedDirectory.path
        }?.bookmarkData
    }

    func rememberDirectoryAccess(_ directory: URL) {
        guard let bookmarkData = FileBrowserSecurityScopedBookmarkPolicy.bookmarkData(for: directory) else {
            return
        }

        let standardizedDirectory = directory.standardizedFileURL
        var nextState = state
        nextState.directoryBookmarks.removeAll {
            $0.directory.standardizedFileURL.path == standardizedDirectory.path
        }
        nextState.directoryBookmarks.append(FileBrowserDirectoryBookmark(
            directory: standardizedDirectory,
            bookmarkData: bookmarkData
        ))
        update(nextState)
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save file browser state at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

enum FileBrowserSecurityScopedBookmarkPolicy {
    static func bookmarkData(for directory: URL) -> Data? {
        try? directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func withAccess<T>(
        to directory: URL,
        bookmarkData: Data?,
        perform operation: () throws -> T
    ) rethrows -> T {
        var didStartAccess = false
        var scopedURL: URL?

        if let bookmarkData,
           let resolved = resolveURL(for: bookmarkData, fallbackDirectory: directory) {
            scopedURL = resolved
            didStartAccess = resolved.startAccessingSecurityScopedResource()
        }

        defer {
            if didStartAccess {
                scopedURL?.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private static func resolveURL(for bookmarkData: Data, fallbackDirectory: URL) -> URL? {
        var isStale = false
        if let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale {
            return resolved
        }

        return fallbackDirectory
    }
}
