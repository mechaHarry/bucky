import Foundation
import Darwin

// Snapshot and persistence bookkeeping share one lock; bookmark creation and disk I/O stay on the worker.
final class FileBrowserStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let lock = NSRecursiveLock()
    private var stateStorage = FileBrowserPersistedState.defaultValue
    private(set) var state: FileBrowserPersistedState {
        get { withLock { stateStorage } }
        set { withLock { stateStorage = newValue } }
    }
    let fileURL: URL
    private var errorHandlerStorage: ((String) -> Void)?
    var onPersistenceError: ((String) -> Void)? {
        get { withLock { errorHandlerStorage } }
        set { withLock { errorHandlerStorage = newValue } }
    }
    private var persistenceErrorStorage: String?
    private(set) var persistenceError: String? {
        get { withLock { persistenceErrorStorage } }
        set { withLock { persistenceErrorStorage = newValue } }
    }
    private var canWriteStorage = true
    private(set) var canWrite: Bool {
        get { withLock { canWriteStorage } }
        set { withLock { canWriteStorage = newValue } }
    }
    private var durableState = FileBrowserPersistedState.defaultValue
    private var saveGeneration = 0
    private static let maximumFileBytes = 8 * 1024 * 1024
    private let queue = DispatchQueue(label: "local.bucky.files.persistence", qos: .utility)
    private var pendingSave: (FileBrowserPersistedState, URL?, Int)?
    private var isSaving = false
    private var workerBookmarks: [FileBrowserDirectoryBookmark] = []

    init(
        fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("file-browser.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        load()
    }

    private func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func applyLoadedState(_ loaded: FileBrowserPersistedState) {
        withLock {
            stateStorage = loaded
            durableState = loaded
            canWriteStorage = true
            persistenceErrorStorage = nil
        }
    }

    func load() {
        do {
            var metadata = stat()
            guard lstat(fileURL.path, &metadata) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_size <= Self.maximumFileBytes else { throw CocoaError(.fileReadCorruptFile) }
            let loaded = FileBrowserRetentionPolicy.bounded(try JSONFilePersistence.read(
                FileBrowserPersistedState.self, from: fileURL, decoder: JSONFilePersistence.makeDecoder()
            ))
            applyLoadedState(loaded)
        } catch let error as POSIXError where error.code == .ENOENT {
            applyLoadedState(.defaultValue)
        } catch {
            let message = "Could not read Files preferences. The existing file is preserved; repair it before saving changes."
            let handler = withLock {
                canWriteStorage = false
                persistenceErrorStorage = message
                return errorHandlerStorage
            }
            handler?(message)
        }
    }

    func update(_ nextState: FileBrowserPersistedState) {
        update(nextState, remembering: nil)
    }

    func update(_ nextState: FileBrowserPersistedState, remembering directory: URL?) {
        enqueueUpdate(FileBrowserRetentionPolicy.bounded(nextState), remembering: directory)
    }

    private func enqueueUpdate(_ nextState: FileBrowserPersistedState?, remembering directory: URL?) {
        lock.lock()
        guard canWriteStorage else {
            let handler = errorHandlerStorage
            let message = persistenceErrorStorage ?? "Files preferences cannot be saved."
            lock.unlock()
            handler?(message)
            return
        }
        if let nextState { stateStorage = nextState }
        saveGeneration += 1
        pendingSave = (stateStorage, directory, saveGeneration)
        let shouldStart = !isSaving
        isSaving = true
        if shouldStart {
            queue.async { [self] in drainSaves() }
        }
        lock.unlock()
    }

    func bookmarkData(for directory: URL) -> Data? {
        let standardizedDirectory = directory.standardizedFileURL
        return state.directoryBookmarks.first {
            $0.directory.standardizedFileURL.path == standardizedDirectory.path
        }?.bookmarkData
    }

    func rememberDirectoryAccess(_ directory: URL) {
        enqueueUpdate(nil, remembering: directory)
    }

    private func drainSaves() {
        while true {
            lock.lock()
            guard let (snapshot, directory, generation) = pendingSave else {
                isSaving = false
                lock.unlock()
                return
            }
            pendingSave = nil
            lock.unlock()
            var next = snapshot
            for bookmark in workerBookmarks where !next.directoryBookmarks.contains(where: { $0.directory == bookmark.directory }) {
                next.directoryBookmarks.append(bookmark)
            }
            if let directory,
               let data = FileBrowserSecurityScopedBookmarkPolicy.bookmarkData(for: directory) {
                let bookmark = FileBrowserDirectoryBookmark(directory: directory.standardizedFileURL, bookmarkData: data)
                next.directoryBookmarks.removeAll { $0.directory == bookmark.directory }
                next.directoryBookmarks.append(bookmark)
            }
            next = FileBrowserRetentionPolicy.bounded(next)
            do {
                try JSONFilePersistence.write(next, to: fileURL, fileManager: fileManager,
                                              encoder: JSONFilePersistence.makeEncoder())
                workerBookmarks = next.directoryBookmarks
                let saved = next
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.withLock {
                        self.durableState = saved
                        if generation == self.saveGeneration {
                            self.stateStorage = saved
                        } else {
                            for bookmark in saved.directoryBookmarks where !self.stateStorage.directoryBookmarks.contains(where: { $0.directory == bookmark.directory }) {
                                self.stateStorage.directoryBookmarks.append(bookmark)
                            }
                            self.stateStorage = FileBrowserRetentionPolicy.bounded(self.stateStorage)
                        }
                        self.persistenceErrorStorage = nil
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let handler = self.withLock {
                        if generation == self.saveGeneration { self.stateStorage = self.durableState }
                        self.persistenceErrorStorage = "Could not save Files preferences."
                        return self.errorHandlerStorage
                    }
                    handler?("Could not save Files preferences.")
                }
            }
        }
    }

    /// A durability barrier for targeted tests and explicit shutdown integration.
    func flush(completion: @escaping () -> Void) {
        withLock {
            queue.async { DispatchQueue.main.async(execute: completion) }
        }
    }
}

enum FileBrowserRetentionPolicy {
    static let historyLimit = 128
    static let selectionLimit = 256
    static let bookmarkLimit = 256
    static let pinLimit = 128

    static func bounded(_ state: FileBrowserPersistedState) -> FileBrowserPersistedState {
        var next = state
        next.traversalChain = Array(state.traversalChain.prefix(historyLimit))
        next.rememberedSelections = Array(state.rememberedSelections.suffix(selectionLimit))
        // Existing pins are user data. Keep their access bookmarks even for legacy states over the pin limit.
        let protected = Set((state.pinnedDirectories + state.pinnedDirectories.map { $0.deletingLastPathComponent() }
            + [state.lastDirectory].compactMap { $0 }).map { $0.standardizedFileURL })
        let pinned = state.directoryBookmarks.filter { protected.contains($0.directory.standardizedFileURL) }
        let recent = state.directoryBookmarks.filter { !protected.contains($0.directory.standardizedFileURL) }
        next.directoryBookmarks = Array(recent.suffix(max(0, bookmarkLimit - pinned.count))) + pinned
        return next
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
