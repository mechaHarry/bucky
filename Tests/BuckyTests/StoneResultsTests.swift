import XCTest
@testable import Bucky

final class StoneResultsTests: XCTestCase {
    @MainActor
    @available(macOS 26.0, *)
    func testAdditionalTextStoneProviderParticipatesInLauncherBehavior() throws {
        let provider = AdditionalTextStoneProvider()
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

        XCTAssertEqual(
            model.availableModes.map(\.stoneID),
            [.applications, .calculator, .dictionary, .files, provider.definition.id]
        )
        let mode = try XCTUnwrap(model.availableModes.last)
        XCTAssertEqual(mode.shortTitle, "Notes")
        XCTAssertEqual(mode.placeholder, "Search Notes Here")
        XCTAssertEqual(mode.helpSystemImage, "note.text")
        XCTAssertEqual(mode.shortcutDisplayText, "Command+5")
        XCTAssertEqual(mode.stoneDefinition.updatePolicy, .deferred(delayNanoseconds: 5_000_000))
        XCTAssertEqual(mode.stoneDefinition.tint, provider.definition.tint)
        XCTAssertEqual(model.mode(forCommandNumber: 5), mode)

        _ = model.handle(command: .previousMode)
        XCTAssertEqual(model.mode, mode)
        _ = model.handle(command: .nextMode)
        XCTAssertEqual(model.mode, .applications)

        _ = model.handle(command: .switchMode(mode))
        model.query = "first"
        model.queryDidChange()

        XCTAssertEqual(model.resultSnapshot, .loading(message: "Preparing first"))
        waitUntil(model.resultSnapshot.rows.map(\.display) == ["Note: first"])
        XCTAssertEqual(provider.updatedQueries.last, "first")

        _ = model.handle(command: .switchMode(.calculator))
        _ = model.handle(command: .switchMode(mode))
        XCTAssertEqual(model.query, "first")

        model.query = "cancelled"
        model.queryDidChange()
        _ = model.handle(command: .switchMode(.applications))
        XCTAssertGreaterThan(provider.cancelCount, 0)

        _ = model.handle(command: .switchMode(mode))
        model.query = "activate"
        model.queryDidChange()
        waitUntil(model.resultSnapshot.rows.map(\.display) == ["Note: activate"])
        let row = try XCTUnwrap(model.resultSnapshot.rows.first)
        model.activate(row)

        XCTAssertEqual(provider.performedActivations, [.copy("activate")])
    }

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

@MainActor
private final class AdditionalTextStoneProvider: TextStoneProvider {
    let definition = StoneDefinition(
        id: StoneID(rawValue: 50),
        shortcutNumber: 5,
        presentation: StonePresentation(
            title: "Notes",
            placeholder: "Search Notes Here",
            systemImage: "note.text"
        ),
        surface: .textInput,
        updatePolicy: .deferred(delayNanoseconds: 5_000_000),
        tint: StoneTint(
            activeHex: 0x406080,
            panelHex: 0x304860,
            iconHex: 0x203040,
            darkModeIconHex: 0xB0C0D0
        )
    )
    private(set) var updatedQueries: [String] = []
    private(set) var cancelCount = 0
    private(set) var performedActivations: [StoneActivation] = []

    func snapshot(for query: String) -> StoneResultSnapshot {
        .loading(message: "Preparing \(query)")
    }

    func updateSnapshot(for query: String) async -> StoneResultSnapshot {
        updatedQueries.append(query)
        return .loaded(rows: [StoneResultRow(
            id: .tool(kind: .message, key: "notes:\(query)"),
            display: "Note: \(query)",
            subtitle: "Neutral text provider",
            copyText: query,
            kind: .message,
            primaryActivation: .none,
            accessoryActivation: .none
        )])
    }

    func cancel() {
        cancelCount += 1
    }

    func activation(for row: StoneResultRow) -> StoneActivation {
        .copy(row.copyText ?? "")
    }

    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> TextStoneActivationResult {
        performedActivations.append(activation)
        return .handled(shouldRefresh: false, resetSelection: false, shouldHide: false)
    }
}
