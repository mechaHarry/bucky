import Foundation
import XCTest
@testable import Bucky

final class JSONFilePersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyJSONFilePersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testReadDecodesJSONFileContents() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("fixture.json")
        let value = PersistedFixture(values: ["one", "two"])
        try makeEncoder().encode(value).write(to: fileURL, options: .atomic)

        let decoded = try JSONFilePersistence.read(
            PersistedFixture.self,
            from: fileURL,
            decoder: makeDecoder()
        )

        XCTAssertEqual(decoded, value)
    }

    func testWriteCreatesParentDirectoriesAndPersistsValue() throws {
        let fileURL = temporaryDirectory
            .appendingPathComponent("nested")
            .appendingPathComponent("deeper")
            .appendingPathComponent("fixture.json")
        let value = PersistedFixture(values: ["b", "a"])

        try JSONFilePersistence.write(
            value,
            to: fileURL,
            fileManager: .default,
            encoder: makeEncoder()
        )

        let reloaded = try JSONFilePersistence.read(
            PersistedFixture.self,
            from: fileURL,
            decoder: makeDecoder()
        )

        XCTAssertEqual(reloaded, value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
    }

    func testWritePropagatesDirectoryCreationErrors() throws {
        let blockedDirectory = temporaryDirectory.appendingPathComponent("blocked")
        try Data().write(to: blockedDirectory, options: .atomic)

        XCTAssertThrowsError(
            try JSONFilePersistence.write(
                PersistedFixture(values: ["value"]),
                to: blockedDirectory.appendingPathComponent("fixture.json"),
                fileManager: .default,
                encoder: makeEncoder()
            )
        )
    }

    func testInclusionStoreMissingFileDefaultsToEmptySetAndCreatesBackingFile() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("inclusions.json")

        let store = InclusionStore(fileURL: fileURL)

        XCTAssertEqual(store.sortedPaths(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let persisted = try JSONDecoder().decode(InclusionsFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.includedPaths, [])
    }

    func testInclusionStoreMalformedFileDefaultsToEmptySetAndRewritesValidJSON() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("inclusions.json")
        try Data("not json".utf8).write(to: fileURL, options: .atomic)

        let store = InclusionStore(fileURL: fileURL)

        XCTAssertEqual(store.sortedPaths(), [])
        let persisted = try JSONDecoder().decode(InclusionsFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.includedPaths, [])
    }

    func testInclusionStorePersistsUniqueSortedPaths() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("inclusions.json")
        let store = InclusionStore(fileURL: fileURL)

        store.add(path: "/Applications/Zeta.app")
        store.add(path: "/Applications/Alpha.app")
        store.add(path: "/Applications/Zeta.app")

        let reloaded = InclusionStore(fileURL: fileURL)

        XCTAssertEqual(reloaded.sortedPaths(), [
            "/Applications/Alpha.app",
            "/Applications/Zeta.app"
        ])
    }

    func testExclusionStoreMissingFileDefaultsToEmptySet() {
        let fileURL = temporaryDirectory.appendingPathComponent("exclusions.json")

        let store = ExclusionStore(fileURL: fileURL)

        XCTAssertEqual(store.sortedPaths(), [])
    }

    func testExclusionStoreMalformedFileDefaultsToEmptySet() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("exclusions.json")
        try Data("not json".utf8).write(to: fileURL, options: .atomic)

        let store = ExclusionStore(fileURL: fileURL)

        XCTAssertEqual(store.sortedPaths(), [])
    }

    func testDictionaryHistoryStoreMissingFileDefaultsToEmptyHistory() {
        let fileURL = temporaryDirectory.appendingPathComponent("dictionary-history.json")

        let store = DictionaryHistoryStore(fileURL: fileURL)

        XCTAssertEqual(store.words, [])
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

private struct PersistedFixture: Codable, Equatable {
    let values: [String]
}
