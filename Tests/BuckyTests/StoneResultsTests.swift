import XCTest
@testable import Bucky

final class StoneResultsTests: XCTestCase {
    func testSnapshotStatesExposeRowsAndSurfaceMessages() {
        let messageRow = StoneResultRow(
            id: .tool(kind: .message, key: "message:complete"),
            display: "Complete the calculation",
            subtitle: "2 +",
            copyText: nil,
            kind: .message,
            primaryActivation: .none,
            accessoryActivation: .none
        )
        let loadedRow = StoneResultRow(
            id: .tool(kind: .calculation, key: "calculation:2 + 2"),
            display: "4",
            subtitle: "2 + 2 =",
            copyText: "4",
            kind: .calculation,
            primaryActivation: .copy("4"),
            accessoryActivation: .copy("4")
        )

        XCTAssertEqual(StoneResultSnapshot.loading(message: "Loading apps").surfaceMessage, "Loading apps")
        XCTAssertEqual(StoneResultSnapshot.empty(message: "No matches").surfaceMessage, "No matches")
        XCTAssertEqual(StoneResultSnapshot.message(messageRow).rows, [messageRow])
        XCTAssertNil(StoneResultSnapshot.message(messageRow).surfaceMessage)
        XCTAssertEqual(StoneResultSnapshot.loaded(rows: [loadedRow]).rows, [loadedRow])
        XCTAssertNil(StoneResultSnapshot.loaded(rows: [loadedRow]).surfaceMessage)
    }

    func testApplicationRowsUseStableApplicationIDs() {
        let id = AppRowID(rawValue: 42)
        let url = URL(fileURLWithPath: "/Applications/Notes.app")
        let original = LaunchItem(
            title: "Notes",
            subtitle: "/Applications/Notes.app",
            url: url,
            searchText: "notes"
        )
        let refreshed = LaunchItem(
            title: "Notes",
            subtitle: "Notes.app",
            url: url,
            searchText: "notes app"
        )

        XCTAssertEqual(
            StoneResultRow.application(id: id, item: original).id,
            StoneResultRow.application(id: id, item: refreshed).id
        )
    }

    func testToolHistoryRowsUseStableIDsIndependentOfDisplaySubtitle() {
        let first = ToolItem(
            title: "2 + 2 = 4",
            subtitle: "Calculated 8/28/26, 4:00 PM",
            copyText: "4",
            kind: .calculationHistory
        )
        let refreshed = ToolItem(
            title: "2 + 2 = 4",
            subtitle: "Calculated 8/28/26, 4:01 PM",
            copyText: "4",
            kind: .calculationHistory
        )

        XCTAssertEqual(
            StoneResultRow.tool(first).id,
            StoneResultRow.tool(refreshed).id
        )
    }

    func testToolRowsExposeActivationIntentsWithoutSideEffects() throws {
        let calculation = StoneResultRow.tool(ToolItem(
            title: "4",
            subtitle: "2 + 2 =",
            copyText: "4",
            kind: .calculation
        ))
        let dictionary = StoneResultRow.tool(ToolItem(
            title: "apple",
            subtitle: "A fruit",
            copyText: nil,
            kind: .dictionary
        ))
        let history = StoneResultRow.tool(ToolItem(
            title: "banana",
            subtitle: "Opened 8/28/26, 4:00 PM",
            copyText: nil,
            kind: .dictionaryHistory
        ))
        let message = StoneResultRow.tool(ToolItem(
            title: "No dictionary matches",
            subtitle: "zzzz",
            copyText: nil,
            kind: .message
        ))

        XCTAssertEqual(calculation.primaryActivation, .copy("4"))
        XCTAssertEqual(calculation.accessoryActivation, .copy("4"))
        XCTAssertEqual(dictionary.primaryActivation, .open(.url(try XCTUnwrap(URL(string: "dict://apple")))))
        XCTAssertEqual(dictionary.accessoryActivation, .open(.url(try XCTUnwrap(URL(string: "dict://apple")))))
        XCTAssertEqual(history.accessoryActivation, .removeHistory(history.id))
        XCTAssertEqual(message.primaryActivation, .none)
        XCTAssertEqual(message.accessoryActivation, .none)
    }

    func testResultRequestGateRejectsStaleAndCancelledRequests() {
        var gate = StoneResultRequestGate()

        let stale = gate.begin(query: "app")
        let latest = gate.begin(query: "apple")

        XCTAssertFalse(gate.accepts(stale, currentQuery: "apple"))
        XCTAssertTrue(gate.accepts(latest, currentQuery: "apple"))

        gate.cancel()

        XCTAssertFalse(gate.accepts(latest, currentQuery: "apple"))
    }

    @MainActor
    @available(macOS 26.0, *)
    func testDeferredDictionarySnapshotSuppressesStaleLookupResult() {
        let lookup = DelayedDictionaryLookup()
        let model = makeDictionaryLauncherModel(
            dictionaryLookup: { query in lookup.results(for: query) }
        )

        model.show(mode: .dictionary)
        model.query = "app"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.11))

        model.query = "apple"
        model.queryDidChange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.24))

        XCTAssertEqual(lookup.queries.sorted(), ["app", "apple"])
        XCTAssertEqual(model.resultSnapshot.rows.map(\.display), ["apple"])
        XCTAssertEqual(model.resultSnapshot.rows.map(\.subtitle), ["Definition for apple"])
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCancellingDeferredDictionaryLookupPreventsPendingSnapshot() {
        let lookup = DelayedDictionaryLookup()
        let model = makeDictionaryLauncherModel(
            dictionaryLookup: { query in lookup.results(for: query) }
        )

        model.show(mode: .dictionary)
        model.query = "banana"
        model.queryDidChange()
        model.show(mode: .calculator)
        RunLoop.current.run(until: Date().addingTimeInterval(0.14))

        XCTAssertEqual(lookup.queries, [])
        XCTAssertEqual(model.resultSnapshot.surfaceMessage, "No calculation history")
    }

    @MainActor
    @available(macOS 26.0, *)
    private func makeDictionaryLauncherModel(
        dictionaryLookup: @escaping @Sendable (String) -> [DictionaryResult]
    ) -> LiquidGlassLauncherModel {
        LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL()),
            dictionaryLookup: dictionaryLookup,
            dictionaryOpenHandler: { _ in },
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )
    }

    private func temporaryDictionaryHistoryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyDictionaryHistory-\(UUID().uuidString).json")
    }

    private final class DelayedDictionaryLookup: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedQueries: [String] = []

        var queries: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedQueries
        }

        func results(for query: String) -> [DictionaryResult] {
            lock.lock()
            recordedQueries.append(query)
            lock.unlock()

            if query == "app" {
                Thread.sleep(forTimeInterval: 0.16)
            }

            return [
                DictionaryResult(
                    term: query,
                    definition: "Definition for \(query)"
                )
            ]
        }
    }
}
