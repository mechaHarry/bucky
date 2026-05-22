import AppKit
import Foundation
@testable import Bucky

struct StubFileSystemClient: FileSystemClientProtocol {
    let home: URL
    var entriesByDirectory: [URL: [FileBrowserEntry]]
    var resolvedDirectoriesByURL: [URL: URL] = [:]

    func homeDirectory() -> URL { home }

    func parentURL(for url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    func isDirectory(_ url: URL) -> Bool {
        resolvedDirectoryURL(for: url) != nil
    }

    func resolvedDirectoryURL(for url: URL) -> URL? {
        if let resolved = resolvedDirectoriesByURL.first(where: {
            $0.key.standardizedFileURL.path == url.standardizedFileURL.path
        })?.value {
            return resolved.standardizedFileURL
        }

        if url.hasDirectoryPath || entriesByDirectory.matching(url) != nil {
            return url.standardizedFileURL
        }

        return nil
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        entriesByDirectory.matching(directory) ?? []
    }
}

final class InMemoryFileBrowserStore: FileBrowserPersisting {
    private(set) var state: FileBrowserPersistedState
    private(set) var rememberedAccessDirectories: [URL] = []

    init(state: FileBrowserPersistedState) {
        self.state = state
    }

    func update(_ nextState: FileBrowserPersistedState) {
        state = nextState
    }

    func bookmarkData(for directory: URL) -> Data? {
        state.directoryBookmarks.first {
            $0.directory.standardizedFileURL.path == directory.standardizedFileURL.path
        }?.bookmarkData
    }

    func rememberDirectoryAccess(_ directory: URL) {
        rememberedAccessDirectories.append(directory.standardizedFileURL)
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

    func isDirectory(_ url: URL) -> Bool {
        resolvedDirectoryURL(for: url) != nil
    }

    func resolvedDirectoryURL(for url: URL) -> URL? {
        if url.hasDirectoryPath || entriesByDirectory.matching(url) != nil {
            return url.standardizedFileURL
        }

        return nil
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        entryRequests.append((directory, sort))
        return entriesByDirectory.matching(directory) ?? []
    }
}

final class ThrowingFileSystemClient: FileSystemClientProtocol {
    private let home: URL
    private let entriesByDirectory: [URL: [FileBrowserEntry]]
    private let throwingDirectories: Set<URL>
    private(set) var entryRequests: [(directory: URL, sort: FileBrowserSort)] = []

    init(home: URL, entriesByDirectory: [URL: [FileBrowserEntry]], throwingDirectories: Set<URL>) {
        self.home = home
        self.entriesByDirectory = entriesByDirectory
        self.throwingDirectories = throwingDirectories
    }

    func homeDirectory() -> URL { home }

    func parentURL(for url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    func isDirectory(_ url: URL) -> Bool {
        resolvedDirectoryURL(for: url) != nil
    }

    func resolvedDirectoryURL(for url: URL) -> URL? {
        if url.hasDirectoryPath || entriesByDirectory.matching(url) != nil {
            return url.standardizedFileURL
        }

        return nil
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        entryRequests.append((directory, sort))
        if throwingDirectories.containsPath(matching: directory) {
            throw TestFileBrowserServiceError.failed
        }
        return entriesByDirectory.matching(directory) ?? []
    }
}

@MainActor
final class ManualDirectoryStream: FileBrowserDirectoryStreaming {
    private(set) var requests: [(directory: URL, sort: FileBrowserSort)] = []
    private var completions: [(Result<[FileBrowserEntry], Error>) -> Void] = []

    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    ) {
        requests.append((directory, sort))
        completions.append(completion)
    }

    func completeRequest(at index: Int, with result: Result<[FileBrowserEntry], Error>) {
        completions[index](result)
    }
}

@MainActor
struct ImmediateDirectoryStream: FileBrowserDirectoryStreaming {
    var fileSystem: FileSystemClientProtocol?

    init(fileSystem: FileSystemClientProtocol? = nil) {
        self.fileSystem = fileSystem
    }

    func loadEntries(
        in directory: URL,
        sort: FileBrowserSort,
        completion: @escaping (Result<[FileBrowserEntry], Error>) -> Void
    ) {
        do {
            completion(.success(try fileSystem?.entries(in: directory, sort: sort) ?? []))
        } catch {
            completion(.failure(error))
        }
    }
}

final class ManualDirectoryObserver: FileBrowserDirectoryObserving {
    private(set) var observedDirectories: [URL] = []
    private var observations: [ManualDirectoryObservation] = []

    func observe(
        directory: URL,
        onChange: @escaping @MainActor () -> Void
    ) -> FileBrowserDirectoryObservation? {
        observedDirectories.append(directory.standardizedFileURL)
        let observation = ManualDirectoryObservation(onChange: onChange)
        observations.append(observation)
        return observation
    }

    @MainActor
    func triggerLatestChange() {
        observations.last?.trigger()
    }
}

private final class ManualDirectoryObservation: FileBrowserDirectoryObservation {
    private let onChange: @MainActor () -> Void
    private(set) var isCancelled = false

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func cancel() {
        isCancelled = true
    }

    @MainActor
    func trigger() {
        guard !isCancelled else { return }
        onChange()
    }
}

private extension Dictionary where Key == URL, Value == [FileBrowserEntry] {
    func matching(_ directory: URL) -> [FileBrowserEntry]? {
        first { $0.key.standardizedFileURL.path == directory.standardizedFileURL.path }?.value
    }
}

private extension Set where Element == URL {
    func containsPath(matching directory: URL) -> Bool {
        contains { $0.standardizedFileURL.path == directory.standardizedFileURL.path }
    }
}

enum TestFileBrowserServiceError: LocalizedError {
    case failed

    var errorDescription: String? { "failed" }
}

final class RecordingFileBrowserServices: FileBrowserNativeServicing {
    struct ThumbnailRequest: Equatable {
        let url: URL
        let size: CGSize
        let scale: CGFloat
    }

    enum Event: Equatable {
        case open(URL)
        case revealInFinder([URL])
        case copyPaths([URL])
        case copy([URL], URL, FileBrowserConflictResolution)
        case move([URL], URL, FileBrowserConflictResolution)
        case trash([URL])
        case unmount(URL)
        case rename(URL, String)
        case batchRename([URL], String)
    }

    var events: [Event] = []
    var conflicts: [FileBrowserConflict] = []
    var error: Error?
    var iconResult = NSImage(size: NSSize(width: 16, height: 16))
    var previewMode: FileBrowserPreviewMode = .metadataFallback
    var previewModesByURL: [URL: FileBrowserPreviewMode] = [:]
    var thumbnailResult: NSImage?
    private(set) var iconRequests: [URL] = []
    private(set) var thumbnailRequests: [ThumbnailRequest] = []

    func reset() {
        events = []
        conflicts = []
        error = nil
        iconRequests = []
        thumbnailResult = nil
        thumbnailRequests = []
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

    func icon(for url: URL) -> NSImage {
        iconRequests.append(url)
        return iconResult
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

    func unmount(_ url: URL) throws {
        if let error { throw error }
        events.append(.unmount(url))
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

    func previewMode(for url: URL) -> FileBrowserPreviewMode {
        previewModesByURL[url] ?? previewMode
    }

    func loadPreviewThumbnail(
        for url: URL,
        size: CGSize,
        scale: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) {
        thumbnailRequests.append(ThumbnailRequest(url: url, size: size, scale: scale))
        completion(thumbnailResult)
    }
}
