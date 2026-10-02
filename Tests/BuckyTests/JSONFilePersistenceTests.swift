import Foundation
import Darwin
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

    func testReadRejectsFIFOAndDirectoryWithoutWaitingForAWriter() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("pipe.json")
        XCTAssertEqual(mkfifo(fileURL.path, 0o600), 0)
        XCTAssertThrowsError(try JSONFilePersistence.read(PersistedFixture.self, from: fileURL, decoder: makeDecoder()))
        XCTAssertThrowsError(try JSONFilePersistence.read(PersistedFixture.self, from: temporaryDirectory, decoder: makeDecoder()))
    }

    func testReadRejectsSymlinkWithoutChangingItsTarget() throws {
        let target = temporaryDirectory.appendingPathComponent("target.json")
        let fileURL = temporaryDirectory.appendingPathComponent("link.json")
        let bytes = try makeEncoder().encode(PersistedFixture(values: ["original"]))
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        XCTAssertThrowsError(try JSONFilePersistence.read(PersistedFixture.self, from: fileURL, decoder: makeDecoder()))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testOversizedWritePreservesExistingData() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("fixture.json")
        let original = PersistedFixture(values: ["original"])
        try JSONFilePersistence.write(original, to: fileURL)
        XCTAssertThrowsError(try JSONFilePersistence.write(
            PersistedFixture(values: [String(repeating: "x", count: JSONFilePersistence.maximumFileBytes + 1)]), to: fileURL))
        XCTAssertEqual(try JSONFilePersistence.read(PersistedFixture.self, from: fileURL, decoder: makeDecoder()), original)
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

    func testInclusionStoreMalformedFileDefaultsToEmptySetAndPreservesFile() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("inclusions.json")
        try Data("not json".utf8).write(to: fileURL, options: .atomic)

        let store = InclusionStore(fileURL: fileURL)

        XCTAssertEqual(store.sortedPaths(), [])
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("not json".utf8))
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.add(path: "/Applications/Example.app"))
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("not json".utf8))
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
