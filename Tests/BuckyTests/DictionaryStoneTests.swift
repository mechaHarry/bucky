import XCTest
@testable import Bucky

final class DictionaryStoneTests: XCTestCase {
    @MainActor
    func testBlankQueryWithoutHistoryReturnsEmptyLoadedSnapshot() {
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { _ in [] }
        )

        let snapshot = stone.snapshot(for: "   ")

        XCTAssertEqual(snapshot, .loaded(rows: []))
        XCTAssertNil(snapshot.surfaceMessage)
    }

    @MainActor
    func testBlankQueryWithHistoryReturnsPersistedHistoryRowsInStoreOrder() {
        let store = makeStore()
        store.add(term: "apple")
        store.add(term: "banana")
        let stone = DictionaryStone(
            historyStore: store,
            lookup: { _ in [] }
        )

        let rows = stone.snapshot(for: "").rows

        XCTAssertEqual(rows.map(\.kind), [.dictionaryHistory, .dictionaryHistory])
        XCTAssertEqual(rows.map(\.display), ["banana", "apple"])
        XCTAssertTrue(rows.allSatisfy { $0.copyText == nil })
        XCTAssertTrue(rows.allSatisfy { $0.subtitle.hasPrefix("Opened ") })
    }

    @MainActor
    func testLookupSuccessMapsResultsToLoadedDictionaryRows() async throws {
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { query in
                [
                    DictionaryResult(term: query, definition: "A fruit\nwith crisp flesh."),
                    DictionaryResult(term: "banana", definition: "A yellow fruit.")
                ]
            }
        )

        XCTAssertEqual(stone.snapshot(for: " apple "), .loading(message: "Searching Dictionary"))
        let rows = try loadedRows(await stone.lookupResults(for: " apple "))

        XCTAssertEqual(rows.map(\.kind), [.dictionary, .dictionary])
        XCTAssertEqual(rows.map(\.display), ["apple", "banana"])
        XCTAssertEqual(rows.map(\.subtitle), ["A fruit with crisp flesh.", "A yellow fruit."])
        XCTAssertTrue(rows.allSatisfy { $0.copyText == nil })
    }

    @MainActor
    func testLookupEmptyResponseReturnsNoMatchMessage() async {
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { _ in [] }
        )

        XCTAssertEqual(stone.snapshot(for: "zzzz"), .loading(message: "Searching Dictionary"))
        let snapshot = await stone.lookupResults(for: "zzzz")

        XCTAssertEqual(snapshot.rows.map(\.display), ["No dictionary matches"])
        XCTAssertEqual(snapshot.rows.map(\.subtitle), ["zzzz"])
        XCTAssertEqual(snapshot.rows.map(\.kind), [.message])
        XCTAssertNil(snapshot.surfaceMessage)
    }

    @MainActor
    func testLookupDedupesNormalizedDuplicateTermsPreservingFirstResult() async throws {
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { _ in
                [
                    DictionaryResult(term: "Apple", definition: "First definition."),
                    DictionaryResult(term: " apple ", definition: "Second definition."),
                    DictionaryResult(term: "Banana", definition: "Third definition.")
                ]
            }
        )

        XCTAssertEqual(stone.snapshot(for: "apple"), .loading(message: "Searching Dictionary"))
        let rows = try loadedRows(await stone.lookupResults(for: "apple"))

        XCTAssertEqual(rows.map(\.display), ["Apple", "Banana"])
        XCTAssertEqual(rows.map(\.subtitle), ["First definition.", "Third definition."])
    }

    @MainActor
    func testHistoryRowIDUsesPersistedEntryIDNotDisplayOrDate() throws {
        let id = UUID(uuidString: "E12FD09E-775E-4B3E-955F-E949559539B4")!
        let first = DictionaryHistoryEntry(
            id: id,
            term: "apple",
            date: Date(timeIntervalSinceReferenceDate: 100)
        )
        let refreshed = DictionaryHistoryEntry(
            id: id,
            term: "apple",
            date: Date(timeIntervalSinceReferenceDate: 200)
        )
        let firstRow = DictionaryStone.historyRow(for: first)
        let refreshedRow = DictionaryStone.historyRow(for: refreshed)

        XCTAssertEqual(firstRow.id, refreshedRow.id)
        XCTAssertEqual(firstRow.id, .tool(kind: .dictionaryHistory, key: "history:E12FD09E-775E-4B3E-955F-E949559539B4"))
    }

    @MainActor
    func testDictionaryRowsExposeResultAndHistoryRemovalActivations() throws {
        let resultRow = try XCTUnwrap(DictionaryStone.resultRows(
            for: [
                DictionaryResult(term: "ice cream", definition: "A frozen dessert.")
            ],
            query: "ice cream"
        ).first)
        let historyRow = DictionaryStone.historyRow(for: DictionaryHistoryEntry(
            id: UUID(uuidString: "AB753325-7B8F-4A03-9B70-6DA8D54BDF67")!,
            term: "banana",
            date: Date(timeIntervalSinceReferenceDate: 0)
        ))
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { _ in [] }
        )

        XCTAssertEqual(stone.activation(for: resultRow), .open(.url(try XCTUnwrap(URL(string: "dict://ice%20cream")))))
        XCTAssertEqual(stone.activation(for: historyRow), .open(.url(try XCTUnwrap(URL(string: "dict://banana")))))
        XCTAssertEqual(historyRow.accessoryActivation, .removeHistory(historyRow.id))
    }

    @MainActor
    func testNewerAsyncQueryWaitsForNonCooperativeLookupBeforeStarting() async {
        let lookup = ControllableDictionaryLookup()
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { query in lookup.results(for: query) }
        )

        XCTAssertEqual(stone.snapshot(for: "app"), .loading(message: "Searching Dictionary"))
        let oldTask = Task { await stone.lookupResults(for: "app") }
        await waitUntil(lookup.startedQueries == ["app"])

        XCTAssertEqual(stone.snapshot(for: "apple"), .loading(message: "Searching Dictionary"))
        let newTask = Task { await stone.lookupResults(for: "apple") }
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(lookup.startedQueries, ["app"])

        lookup.finish(query: "app")
        let oldSnapshot = await oldTask.value
        await waitUntil(lookup.startedQueries == ["app", "apple"])

        lookup.finish(query: "apple")
        let newSnapshot = await newTask.value

        XCTAssertEqual(newSnapshot.rows.map(\.display), ["apple"])
        XCTAssertEqual(oldSnapshot, .loading(message: "Searching Dictionary"))
    }

    @MainActor
    func testClearingQueryReleasesPendingLookupWrapperBeforeLookupCompletes() async {
        let lookup = ControllableDictionaryLookup()
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { query in lookup.results(for: query) }
        )
        let completion = Completion()

        XCTAssertEqual(stone.snapshot(for: "app"), .loading(message: "Searching Dictionary"))
        let task = Task {
            _ = await stone.lookupResults(for: "app")
            completion.finish()
        }

        await waitUntil(lookup.startedQueries == ["app"])
        XCTAssertEqual(stone.snapshot(for: ""), .loaded(rows: []))
        await waitUntil(completion.isFinished)

        XCTAssertTrue(completion.isFinished)
        XCTAssertEqual(lookup.startedQueries, ["app"])
        XCTAssertFalse(lookup.isFinished(query: "app"))

        lookup.finish(query: "app")
        _ = await task.value
    }

    @MainActor
    func testLookupResultsIgnoresQueryThatWasNotEstablishedBySnapshot() async {
        let lookup = RecordingDictionaryLookup()
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { query in lookup.results(for: query) }
        )

        XCTAssertEqual(stone.snapshot(for: "apple"), .loading(message: "Searching Dictionary"))
        let snapshot = await stone.lookupResults(for: "app")

        XCTAssertEqual(snapshot, .loading(message: "Searching Dictionary"))
        XCTAssertEqual(lookup.startedQueries, [])
    }

    @MainActor
    func testStaleDelayedLookupCannotInvalidateNewerSnapshotBeforePublication() async {
        let lookup = ControllableDictionaryLookup()
        let stone = DictionaryStone(
            historyStore: makeStore(),
            lookup: { query in lookup.results(for: query) }
        )

        XCTAssertEqual(stone.snapshot(for: "app"), .loading(message: "Searching Dictionary"))
        let oldTask = Task { await stone.lookupResults(for: "app") }
        await waitUntil(lookup.startedQueries == ["app"])

        XCTAssertEqual(stone.snapshot(for: "apple"), .loading(message: "Searching Dictionary"))
        let newTask = Task { await stone.lookupResults(for: "apple") }
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(lookup.startedQueries, ["app"])

        let staleTask = Task {
            await stone.lookupResults(for: "app")
        }

        lookup.finish(query: "app")
        let oldSnapshot = await oldTask.value
        let staleSnapshot = await staleTask.value
        await waitUntil(lookup.startedQueries == ["app", "apple"])

        lookup.finish(query: "apple")
        let newSnapshot = await newTask.value

        XCTAssertEqual(lookup.startedQueries, ["app", "apple"])
        XCTAssertEqual(newSnapshot.rows.map(\.display), ["apple"])
        XCTAssertEqual(oldSnapshot, .loading(message: "Searching Dictionary"))
        XCTAssertEqual(staleSnapshot, .loading(message: "Searching Dictionary"))
    }

    @MainActor
    private func makeStore() -> DictionaryHistoryStore {
        DictionaryHistoryStore(fileURL: temporaryFileURL())
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyDictionaryStone-\(UUID().uuidString).json")
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func loadedRows(
        _ snapshot: StoneResultSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [StoneResultRow] {
        guard case let .loaded(rows) = snapshot else {
            XCTFail("Expected loaded rows, got \(snapshot)", file: file, line: line)
            return []
        }
        return rows
    }
}

private final class RecordingDictionaryLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedQueries: [String] = []

    var startedQueries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedQueries
    }

    func results(for query: String) -> [DictionaryResult] {
        lock.lock()
        recordedQueries.append(query)
        lock.unlock()

        return [
            DictionaryResult(
                term: query,
                definition: "Definition for \(query)"
            )
        ]
    }
}

private final class ControllableDictionaryLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [String: Completion] = [:]
    private var recordedQueries: [String] = []

    var startedQueries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedQueries
    }

    func results(for query: String) -> [DictionaryResult] {
        let completion = completion(for: query)
        lock.lock()
        recordedQueries.append(query)
        lock.unlock()

        completion.wait()

        return [
            DictionaryResult(
                term: query,
                definition: "Definition for \(query)"
            )
        ]
    }

    func finish(query: String) {
        completion(for: query).finish()
    }

    func isFinished(query: String) -> Bool {
        completion(for: query).isFinished
    }

    private func completion(for query: String) -> Completion {
        lock.lock()
        defer { lock.unlock() }
        if let completion = completions[query] {
            return completion
        }

        let completion = Completion()
        completions[query] = completion
        return completion
    }
}

private final class Completion: @unchecked Sendable {
    private let condition = NSCondition()
    private var finished = false

    var isFinished: Bool {
        condition.lock()
        defer { condition.unlock() }
        return finished
    }

    func wait() {
        condition.lock()
        while !finished {
            condition.wait()
        }
        condition.unlock()
    }

    func finish() {
        condition.lock()
        finished = true
        condition.broadcast()
        condition.unlock()
    }
}
