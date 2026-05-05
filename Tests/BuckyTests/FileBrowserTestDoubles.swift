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

enum TestFileBrowserServiceError: LocalizedError {
    case failed

    var errorDescription: String? { "failed" }
}

final class RecordingFileBrowserServices: FileBrowserNativeServicing {
    enum Event: Equatable {
        case open(URL)
        case revealInFinder([URL])
        case copyPaths([URL])
        case copy([URL], URL, FileBrowserConflictResolution)
        case move([URL], URL, FileBrowserConflictResolution)
        case trash([URL])
        case rename(URL, String)
        case batchRename([URL], String)
    }

    var events: [Event] = []
    var conflicts: [FileBrowserConflict] = []
    var error: Error?

    func reset() {
        events = []
        conflicts = []
        error = nil
    }

    func open(_ url: URL) throws {
        if let error { throw error }
        events.append(.open(url))
    }

    func revealInFinder(_ urls: [URL]) throws {
        if let error { throw error }
        events.append(.revealInFinder(urls))
    }

    func copyPathsToPasteboard(_ urls: [URL]) throws {
        if let error { throw error }
        events.append(.copyPaths(urls))
    }

    func copy(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws {
        if let error { throw error }
        events.append(.copy(urls, destinationDirectory, conflict))
    }

    func move(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws {
        if let error { throw error }
        events.append(.move(urls, destinationDirectory, conflict))
    }

    func trash(_ urls: [URL]) throws {
        if let error { throw error }
        events.append(.trash(urls))
    }

    func rename(_ url: URL, to proposedName: String) throws -> URL {
        if let error { throw error }
        events.append(.rename(url, proposedName))
        return url.deletingLastPathComponent().appendingPathComponent(proposedName)
    }

    func batchRename(_ urls: [URL], baseName: String) throws -> [URL] {
        if let error { throw error }
        events.append(.batchRename(urls, baseName))
        return urls.enumerated().map { index, url in
            url.deletingLastPathComponent().appendingPathComponent("\(baseName) \(index + 1).\(url.pathExtension)")
        }
    }

    func conflictingDestinations(for urls: [URL], in destinationDirectory: URL) -> [FileBrowserConflict] {
        conflicts
    }
}
