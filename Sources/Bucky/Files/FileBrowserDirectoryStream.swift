import Foundation

@MainActor
protocol FileBrowserDirectoryStreaming {
    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        foldersFirst: Bool,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    )
}

protocol FileBrowserDirectoryObserving: AnyObject {
    func observe(
        directory: URL,
        onChange: @escaping @MainActor () -> Void
    ) -> FileBrowserDirectoryObservation?
}

protocol FileBrowserDirectoryObservation: AnyObject {
    func cancel()
}

@MainActor
final class FileBrowserDirectoryStream: FileBrowserDirectoryStreaming {
    private let fileSystem: FileSystemClientProtocol
    private weak var accessStore: FileBrowserPersisting?
    private let queue: DispatchQueue

    init(
        fileSystem: FileSystemClientProtocol,
        accessStore: FileBrowserPersisting? = nil,
        queue: DispatchQueue = DispatchQueue(label: "local.bucky.file-browser.directory-stream", qos: .userInitiated)
    ) {
        self.fileSystem = fileSystem
        self.accessStore = accessStore
        self.queue = queue
    }

    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        foldersFirst: Bool,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    ) {
        let fileSystem = DirectoryStreamFileSystemBox(fileSystem: fileSystem)
        let bookmarkData = accessStore?.bookmarkData(for: directory)
        queue.async {
            let result = Result {
                try FileBrowserSecurityScopedBookmarkPolicy.withAccess(
                    to: directory,
                    bookmarkData: bookmarkData
                ) {
                    try fileSystem.entries(in: directory, sort: sort, foldersFirst: foldersFirst)
                }
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}

private struct DirectoryStreamFileSystemBox: @unchecked Sendable {
    private let fileSystem: FileSystemClientProtocol

    init(fileSystem: FileSystemClientProtocol) {
        self.fileSystem = fileSystem
    }

    func entries(in directory: URL, sort: FileBrowserSort, foldersFirst: Bool) throws -> [FileBrowserEntry] {
        try fileSystem.entries(in: directory, sort: sort, foldersFirst: foldersFirst)
    }
}
