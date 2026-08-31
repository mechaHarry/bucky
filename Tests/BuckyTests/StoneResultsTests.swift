import XCTest
@testable import Bucky

final class StoneResultsTests: XCTestCase {
    @MainActor
    @available(macOS 26.0, *)
    func testRegisteredTextStoneProviderDrivesTextModeSnapshot() {
        let provider = LauncherTestTextStoneProvider(
            definition: StoneCatalog.definition(for: .calculator)
        )
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDictionaryHistoryFileURL()),
            dictionaryLookup: { _ in [] },
            dictionaryOpenHandler: { _ in },
            textStoneProviders: [provider],
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )

        model.show(mode: .calculator)
        model.query = "provider input"
        model.queryDidChange()

        XCTAssertEqual(model.resultSnapshot.rows.map(\.display), ["Provided result"])
    }

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
    func testDeferredApplicationFilterCannotRepublishRowsHiddenBySameQueryExclusionRefresh() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyStoneApplicationExclusionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let alpha = LaunchItem(
            title: "Alpha Tool",
            subtitle: "/Applications/AlphaTool.app",
            url: URL(fileURLWithPath: "/Applications/AlphaTool.app"),
            searchText: "shared alpha"
        )
        let beta = LaunchItem(
            title: "Beta Tool",
            subtitle: "/Applications/BetaTool.app",
            url: URL(fileURLWithPath: "/Applications/BetaTool.app"),
            searchText: "shared beta"
        )
        let cache = ApplicationIndexSnapshotCache(
            fileURL: temporaryDirectory.appendingPathComponent("snapshot.json")
        )
        cache.save([alpha, beta])

        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(fileURL: temporaryDirectory.appendingPathComponent("settings.json")),
            inclusionStore: InclusionStore(fileURL: temporaryDirectory.appendingPathComponent("inclusions.json")),
            exclusionStore: ExclusionStore(fileURL: temporaryDirectory.appendingPathComponent("exclusions.json")),
            calculationHistoryStore: CalculationHistoryStore(),
            dictionaryHistoryStore: DictionaryHistoryStore(
                fileURL: temporaryDirectory.appendingPathComponent("dictionary-history.json")
            ),
            dictionaryLookup: { _ in [] },
            dictionaryOpenHandler: { _ in },
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            ),
            applicationIndexSnapshotCache: cache
        )

        waitUntil(model.resultSnapshot.rows.map(\.display) == ["Alpha Tool", "Beta Tool"])

        model.query = "shared"
        model.queryDidChange()
        model.exclude(alpha)

        XCTAssertEqual(model.resultSnapshot.rows.map(\.display), ["Beta Tool"])

        RunLoop.current.run(until: Date().addingTimeInterval(0.08))

        XCTAssertEqual(model.resultSnapshot.rows.map(\.display), ["Beta Tool"])
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

    @MainActor
    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), file: file, line: line)
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

@MainActor
private final class LauncherTestTextStoneProvider: TextStoneProvider {
    let definition: StoneDefinition

    init(definition: StoneDefinition) {
        self.definition = definition
    }

    func snapshot(for query: String) -> StoneResultSnapshot {
        .loaded(rows: [StoneResultRow(
            id: .tool(kind: .message, key: "launcher-provider-result"),
            display: "Provided result",
            subtitle: query,
            copyText: nil,
            kind: .message,
            primaryActivation: .none,
            accessoryActivation: .none
        )])
    }

    func updateSnapshot(for query: String) async -> StoneResultSnapshot {
        snapshot(for: query)
    }

    func cancel() {}

    func activation(for row: StoneResultRow) -> StoneActivation {
        row.primaryActivation
    }

    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> TextStoneActivationResult {
        .unhandled
    }
}
