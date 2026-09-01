import XCTest
@testable import Bucky

final class DictionaryHistoryStoreTests: XCTestCase {
    func testDictionaryHistoryEntryContractIncludesStableIdentityAndEquatable() {
        let id = UUID()
        let date = Date()
        let entry = DictionaryHistoryEntry(id: id, term: "apple", date: date)
        let sameEntry = DictionaryHistoryEntry(id: id, term: "apple", date: date)

        assertIdentifiableAndEquatable(entry)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry, sameEntry)
    }

    func testAddDedupesByNormalizedTermAndMovesLatestToTop() {
        let store = makeStore()

        store.add(term: "Apple")
        store.add(term: " apple ")

        XCTAssertEqual(store.words.map(\.term), ["apple"])
    }

    func testAddDedupesByNormalizedTermButPreservesOpenedTerm() {
        let store = makeStore()

        store.add(term: " Résumé ")

        XCTAssertEqual(store.words.map(\.term), ["Résumé"])

        store.add(term: "resume")

        XCTAssertEqual(store.words.map(\.term), ["resume"])
    }

    func testRemoveDeletesSingleNormalizedTerm() {
        let store = makeStore()

        store.add(term: "apple")
        store.add(term: "banana")
        store.remove(term: " APPLE ")

        XCTAssertEqual(store.words.map(\.term), ["banana"])
    }

    func testHistoryPersistsAndCapsAtOneHundredEntries() {
        let fileURL = temporaryFileURL()
        let store = DictionaryHistoryStore(fileURL: fileURL)

        for index in 0..<105 {
            store.add(term: "word-\(index)")
        }

        let reloaded = DictionaryHistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.words.count, 100)
        XCTAssertEqual(reloaded.words.first?.term, "word-104")
        XCTAssertEqual(reloaded.words.last?.term, "word-5")
    }

    func testMalformedFileFallsBackToEmptyHistory() throws {
        let fileURL = temporaryFileURL()
        try Data("not json".utf8).write(to: fileURL)

        let store = DictionaryHistoryStore(fileURL: fileURL)

        XCTAssertEqual(store.words, [])
    }

    private func makeStore() -> DictionaryHistoryStore {
        DictionaryHistoryStore(fileURL: temporaryFileURL())
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyDictionaryHistory-\(UUID().uuidString).json")
    }

    private func assertIdentifiableAndEquatable<Entry: Identifiable & Equatable>(_ entry: Entry) {
        XCTAssertEqual(entry, entry)
    }
}
