import Foundation
@testable import Bucky

struct StubFileSystemClient: FileSystemClientProtocol {
    let home: URL
    var entriesByDirectory: [URL: [FileBrowserEntry]]

    func homeDirectory() -> URL { home }

    func parentURL(for url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        entriesByDirectory[directory] ?? []
    }
}

final class InMemoryFileBrowserStore: FileBrowserPersisting {
    private(set) var state: FileBrowserPersistedState

    init(state: FileBrowserPersistedState) {
        self.state = state
    }

    func update(_ nextState: FileBrowserPersistedState) {
        state = nextState
    }
}

final class RecordingFileSystemClient: FileSystemClientProtocol {
    private let home: URL
    private let entriesByDirectory: [URL: [FileBrowserEntry]]
    private(set) var entryRequests: [(directory: URL, sort: FileBrowserSort)] = []

    init(home: URL, entriesByDirectory: [URL: [FileBrowserEntry]]) {
        self.home = home
        self.entriesByDirectory = entriesByDirectory
    }

    func homeDirectory() -> URL { home }

    func parentURL(for url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        entryRequests.append((directory, sort))
        return entriesByDirectory[directory] ?? []
    }
}
