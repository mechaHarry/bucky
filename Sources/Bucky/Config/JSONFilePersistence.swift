import Foundation

enum JSONFilePersistence {
    static func read<Value: Decodable>(
        _ type: Value.Type,
        from fileURL: URL,
        decoder: JSONDecoder
    ) throws -> Value {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(type, from: data)
    }

    static func write<Value: Encodable>(
        _ value: Value,
        to fileURL: URL,
        fileManager: FileManager,
        encoder: JSONEncoder
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
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
