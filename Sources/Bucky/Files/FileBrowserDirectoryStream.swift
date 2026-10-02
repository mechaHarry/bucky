import Foundation

@MainActor
protocol FileBrowserDirectoryStreaming {
    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        foldersFirst: Bool,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    )
    func cancelPendingLoads()
}

extension FileBrowserDirectoryStreaming {
    func cancelPendingLoads() {}
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
    private let worker: FileBrowserLatestWorkQueue
    private var pendingLoad: FileBrowserCancellation?

    init(
        fileSystem: FileSystemClientProtocol,
        accessStore: FileBrowserPersisting? = nil,
        queue: DispatchQueue = DispatchQueue(label: "local.bucky.file-browser.directory-stream", qos: .userInitiated)
    ) {
        self.fileSystem = fileSystem
        self.accessStore = accessStore
        self.worker = FileBrowserLatestWorkQueue(queue: queue)
    }

    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        foldersFirst: Bool,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    ) {
        pendingLoad?.cancel()
        let cancellation = FileBrowserCancellation()
        pendingLoad = cancellation
        let fileSystem = DirectoryStreamFileSystemBox(fileSystem: fileSystem)
        let bookmarkData = accessStore?.bookmarkData(for: directory)
        worker.submit {
            guard !cancellation.isCancelled else { return }
            let result = Result {
                try FileBrowserSecurityScopedBookmarkPolicy.withAccess(
                    to: directory,
                    bookmarkData: bookmarkData
                ) {
                    try fileSystem.entries(in: directory, sort: sort, foldersFirst: foldersFirst, cancellation: cancellation)
                }
            }

            DispatchQueue.main.async {
                guard !cancellation.isCancelled else { return }
                completion(result)
            }
        }
    }

    func cancelPendingLoads() {
        pendingLoad?.cancel()
        pendingLoad = nil
        worker.cancelPending()
    }

    deinit {
        pendingLoad?.cancel()
        worker.cancelPending()
    }
}

private struct DirectoryStreamFileSystemBox: @unchecked Sendable {
    private let fileSystem: FileSystemClientProtocol

    init(fileSystem: FileSystemClientProtocol) {
        self.fileSystem = fileSystem
    }

    func entries(in directory: URL, sort: FileBrowserSort, foldersFirst: Bool, cancellation: FileBrowserCancellation) throws -> [FileBrowserEntry] {
        try fileSystem.entries(in: directory, sort: sort, foldersFirst: foldersFirst, cancellation: cancellation)
    }
}
