import Foundation
import Darwin

enum JSONFilePersistence {
    static let maximumFileBytes = 8 * 1024 * 1024
    // Sync and async operations share one FIFO worker. Encoding also stays off the UI thread.
    private static let worker = DispatchQueue(label: "local.bucky.json-persistence", qos: .utility)
    private static let workerKey: DispatchSpecificKey<Bool> = {
        let key = DispatchSpecificKey<Bool>()
        worker.setSpecific(key: key, value: true)
        return key
    }()

    private static func onWorker<Value>(_ operation: () throws -> Value) rethrows -> Value {
        if DispatchQueue.getSpecific(key: workerKey) == true { return try operation() }
        return try worker.sync(execute: operation)
    }

    static func perform<Value>(_ operation: @escaping () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            worker.async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }

    static func read<Value: Decodable>(
        _ type: Value.Type,
        from fileURL: URL,
        decoder: JSONDecoder
    ) throws -> Value {
        try onWorker { try readOnWorker(type, from: fileURL, decoder: decoder) }
    }

    static func write<Value: Encodable>(
        _ value: Value,
        to fileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = makeEncoder()
    ) throws {
        try onWorker { try writeOnWorker(value, to: fileURL, fileManager: fileManager, encoder: encoder) }
    }

    static func writeAsync<Value: Encodable>(
        _ value: Value,
        to fileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = makeEncoder()
    ) async throws {
        try await perform { try writeOnWorker(value, to: fileURL, fileManager: fileManager, encoder: encoder) }
    }

    static func readAsync<Value: Decodable>(
        _ type: Value.Type,
        from fileURL: URL,
        decoder: JSONDecoder = makeDecoder()
    ) async throws -> Value {
        try await perform { try readOnWorker(type, from: fileURL, decoder: decoder) }
    }

    static func flushAsync() async {
        await withCheckedContinuation { continuation in
            worker.async { continuation.resume() }
        }
    }

    private static func readOnWorker<Value: Decodable>(
        _ type: Value.Type, from fileURL: URL, decoder: JSONDecoder
    ) throws -> Value {
        // Validate the opened descriptor, not just a preflight path. A FIFO must never stall
        // the persistence worker, and a symlink must not redirect reads into unrelated data.
        let descriptor = open(fileURL.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw CocoaError(.fileReadNoSuchFile) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= maximumFileBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard chunk.count <= maximumFileBytes - data.count else { throw CocoaError(.fileReadTooLarge) }
            data.append(chunk)
        }
        return try decoder.decode(type, from: data)
    }

    private static func writeOnWorker<Value: Encodable>(
        _ value: Value, to fileURL: URL, fileManager: FileManager, encoder: JSONEncoder
    ) throws {
        let data = try encoder.encode(value)
        guard data.count <= maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        let directory = fileURL.deletingLastPathComponent()
        try createPrivateDirectories(at: directory, fileManager: fileManager)
        let temporaryURL = directory.appendingPathComponent(".bucky-\(UUID().uuidString).tmp")
        let descriptor = open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? fileManager.removeItem(at: temporaryURL)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        // All fallible preparation precedes replacement, so failures preserve the previous file.
        guard rename(temporaryURL.path, fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func createPrivateDirectories(at directory: URL, fileManager: FileManager) throws {
        var missing: [URL] = []
        var ancestor = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        while !fileManager.fileExists(atPath: ancestor.path, isDirectory: &isDirectory) {
            missing.append(ancestor)
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { throw CocoaError(.fileWriteNoPermission) }
            ancestor = parent
        }
        guard isDirectory.boolValue else { throw CocoaError(.fileWriteFileExists) }
        for url in missing.reversed() {
            // Only directories created here receive private permissions; never chmod existing ancestors.
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
        }
    }

    static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
