import Foundation

enum PersistenceFailure: String, Error, LocalizedError {
    case readFailed = "Could not read saved data. The file has been preserved."
    case writeFailed = "Could not save changes. Your previous data has been preserved."
    case busy = "A save is in progress. Please try again when it finishes."
    case invalidInput = "The supplied value is invalid."

    var errorDescription: String? { rawValue }
}

// Store state is published only after successful persistence. Async transactions refuse overlapping
// mutations rather than allowing stale snapshots to overwrite newer changes.
final class JSONValueStore<Value: Codable> {
    let fileURL: URL
    private let defaultValue: Value
    private let lock = NSRecursiveLock()
    private var storedValue: Value
    private var failure: PersistenceFailure?
    private var readFailed = false
    private var isWriting = false

    var value: Value { withLock { storedValue } }
    var lastError: PersistenceFailure? { withLock { failure } }

    init(fileURL: URL, defaultValue: Value, createMissingFile: Bool = false) {
        self.fileURL = fileURL
        self.defaultValue = defaultValue
        storedValue = defaultValue
        if load(), createMissingFile, !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = mutate { _ in }
        }
    }

    @discardableResult
    func load() -> Bool {
        withLock {
            guard !isWriting else { failure = .busy; return false }
            do {
                storedValue = try JSONFilePersistence.read(Value.self, from: fileURL,
                                                          decoder: JSONFilePersistence.makeDecoder())
                failure = nil
                readFailed = false
                return true
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                storedValue = defaultValue
                failure = nil
                readFailed = false
                return true
            } catch {
                failure = .readFailed
                readFailed = true
                return false
            }
        }
    }

    @discardableResult
    func mutate(_ mutation: (inout Value) -> Void) -> Bool {
        withLock {
            guard !isWriting else { failure = .busy; return false }
            guard !readFailed else { failure = .readFailed; return false }
            var candidate = storedValue
            mutation(&candidate)
            do {
                try JSONFilePersistence.write(candidate, to: fileURL)
                storedValue = candidate
                failure = nil
                return true
            } catch {
                failure = .writeFailed
                return false
            }
        }
    }

    @MainActor @discardableResult
    func loadAsync() async -> Bool {
        guard beginAsyncLoad() else { return false }
        do {
            let loaded = try await JSONFilePersistence.perform {
                try JSONFilePersistence.read(Value.self, from: self.fileURL,
                                             decoder: JSONFilePersistence.makeDecoder())
            }
            return finishAsyncLoad(loaded)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return finishAsyncLoad(defaultValue)
        } catch {
            return withLock {
                failure = .readFailed
                readFailed = true
                isWriting = false
                return false
            }
        }
    }

    private func beginAsyncLoad() -> Bool {
        withLock {
            guard !isWriting else { failure = .busy; return false }
            isWriting = true
            return true
        }
    }

    private func finishAsyncLoad(_ loaded: Value) -> Bool {
        withLock {
            storedValue = loaded
            failure = nil
            readFailed = false
            isWriting = false
            return true
        }
    }

    @MainActor @discardableResult
    func mutateAsync(_ mutation: (inout Value) -> Void) async -> Bool {
        guard let candidate = beginAsyncMutation(mutation) else { return false }
        do {
            try await JSONFilePersistence.perform {
                try JSONFilePersistence.write(candidate, to: self.fileURL)
            }
            return finishAsyncMutation(candidate, succeeded: true)
        } catch {
            return finishAsyncMutation(candidate, succeeded: false)
        }
    }

    private func beginAsyncMutation(_ mutation: (inout Value) -> Void) -> Value? {
        withLock {
            guard !isWriting else { failure = .busy; return nil }
            guard !readFailed else { failure = .readFailed; return nil }
            isWriting = true
            var candidate = storedValue
            mutation(&candidate)
            return candidate
        }
    }

    private func finishAsyncMutation(_ candidate: Value, succeeded: Bool) -> Bool {
        withLock {
            if succeeded { storedValue = candidate }
            failure = succeeded ? nil : .writeFailed
            isWriting = false
            return succeeded
        }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
