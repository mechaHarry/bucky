import Foundation

@MainActor
protocol FileBrowserDirectoryStreaming {
    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    )
}

@MainActor
final class FileBrowserDirectoryStream: FileBrowserDirectoryStreaming {
    private let fileSystem: FileSystemClientProtocol
    private let queue: DispatchQueue

    init(
        fileSystem: FileSystemClientProtocol,
        queue: DispatchQueue = DispatchQueue(label: "com.mechaHarry.bucky.file-browser.directory-stream", qos: .userInitiated)
    ) {
        self.fileSystem = fileSystem
        self.queue = queue
    }

    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    ) {
        let fileSystem = DirectoryStreamFileSystemBox(fileSystem: fileSystem)
        queue.async {
            let result = Result {
                try fileSystem.entries(in: directory, sort: sort)
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

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        try fileSystem.entries(in: directory, sort: sort)
    }
}
