import XCTest
@testable import Bucky

@available(macOS 26.0, *)
@MainActor
final class ApplicationLauncherPerformanceTests: XCTestCase {
    func testCachedRowsReuseSnapshotStorageAcrossSelectionAndRepeatedOpen() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = (0..<256).map { item("Example \($0)") }
        let model = makeModel(directory: directory, cached: items)
        try await waitUntil { model.filteredItemIDs.count == items.count }
        let identity = model.resultSnapshotIdentity
        let storage = model.resultSnapshot.rows.withUnsafeBufferPointer { $0.baseAddress }
        for index in 0..<100 {
            model.selectedIndex = index
            model.setWindowKeyState(index.isMultiple(of: 2))
            XCTAssertEqual(model.resultSnapshotIdentity, identity)
            XCTAssertEqual(model.resultSnapshot.rows.withUnsafeBufferPointer { $0.baseAddress }, storage)
        }
        model.show(mode: .applications)
        model.show(mode: .applications)
        XCTAssertEqual(model.resultSnapshotIdentity, identity)
        XCTAssertEqual(model.resultSnapshot.rows.withUnsafeBufferPointer { $0.baseAddress }, storage)
    }

    func testRapidQueriesPublishLatestResultAndBlankInputResetsSynchronously() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory: directory, cached: (0..<2048).map { item("Example \($0)") })
        try await waitUntil { model.filteredItemIDs.count == 2048 }
        for query in ["example", "example 1", "example 20", "example 2047"] {
            model.query = query
            model.queryDidChange()
        }
        try await waitUntil { model.filteredItems.map(\.title) == ["Example 2047"] }
        let identity = model.resultSnapshotIdentity
        model.queryDidChange() // Cache hit must be immediately available without a scan.
        XCTAssertEqual(model.resultSnapshotIdentity, identity)
        model.query = ""
        model.queryDidChange()
        XCTAssertEqual(model.filteredItemIDs.count, 2048)
    }

    func testExclusionChangesDoNotResurrectHiddenRowsWhenCachePrepares() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exclusions = ExclusionStore(fileURL: directory.appendingPathComponent("exclusions.json"))
        let items = (0..<2048).map { item("Example \($0)") }
        let model = makeModel(directory: directory, cached: items, exclusions: exclusions)
        let excluded = await exclusions.excludeAsync(items[0])
        XCTAssertTrue(excluded)
        model.refreshAfterExclusionsChanged()
        try await waitUntil { model.filteredItemIDs.count == 2047 }
        XCTAssertFalse(model.filteredItems.contains(items[0]))
    }

    func testLiveIndexWinsOverStartupSnapshotIncludingEmptyIndex() async throws {
        for live in [[item("Current")], []] {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = makeModel(directory: directory, cached: [item("Cached")], live: live)
            model.reindex()
            try await waitUntil { !model.isIndexing }
            XCTAssertEqual(model.filteredItems, live)
            // A late startup-cache callback must never overwrite an empty live result.
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(model.filteredItems, live)
        }
    }

    func testRepeatedIdenticalLiveIndexPreservesSnapshotsAndCachedQueries() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = [item("Example 1"), item("Example 2"), item("Example 3")]
        let model = makeModel(directory: directory, cached: items, live: items)
        try await waitUntil { model.filteredItemIDs.count == 3 }
        model.query = "example 1"
        model.queryDidChange()
        try await waitUntil { model.filteredItems.map(\.title) == ["Example 1"] }
        model.query = "example 2"
        model.queryDidChange()
        try await waitUntil { model.filteredItems.map(\.title) == ["Example 2"] }
        let identity = model.resultSnapshotIdentity
        let storage = model.resultSnapshot.rows.withUnsafeBufferPointer { $0.baseAddress }

        for _ in 0..<3 {
            model.reindex()
            try await waitUntil { !model.isIndexing }
            XCTAssertEqual(model.resultSnapshotIdentity, identity)
            XCTAssertEqual(model.resultSnapshot.rows.withUnsafeBufferPointer { $0.baseAddress }, storage)
        }

        // The earlier query must still be a synchronous cache hit after the refreshes.
        model.query = "example 1"
        model.queryDidChange()
        XCTAssertEqual(model.filteredItems.map(\.title), ["Example 1"])
    }

    func testWhitespaceOnlyQueryPreservesExistingScoredOrderingOffMain() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = [item("Long Application"), item("App"), item("Medium")]
        let model = makeModel(directory: directory, cached: items)
        try await waitUntil { model.filteredItemIDs.count == 3 }
        model.query = "   "
        model.queryDidChange()
        try await waitUntil { model.filteredItems.map(\.title) == ["App", "Medium", "Long Application"] }
    }

    func testPendingSearchAndIdleWarmingDoNotRetainModel() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var model: LiquidGlassLauncherModel? = makeModel(directory: directory,
            cached: (0..<2048).map { item("Example \($0)") })
        try await waitUntil { model?.filteredItemIDs.count == 2048 }
        weak var releasedModel = model
        model?.isPresented = true
        model?.query = "example 2047"
        model?.queryDidChange()
        model = nil
        XCTAssertNil(releasedModel, "Foreground work must not retain the launcher model")

        model = makeModel(directory: directory, cached: [item("Example")])
        try await waitUntil { model?.filteredItemIDs.count == 1 }
        releasedModel = model
        model?.isPresented = true
        model?.query = "example"
        model?.startBackgroundWarmCaches()
        model = nil
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertNil(releasedModel, "Delayed warming must not create a model/task cycle")
    }

    private func makeModel(
        directory: URL,
        cached: [LaunchItem],
        exclusions: ExclusionStore? = nil,
        live: [LaunchItem] = []
    ) -> LiquidGlassLauncherModel {
        let cache = ApplicationIndexSnapshotCache(fileURL: directory.appendingPathComponent("index.json"))
        cache.save(cached)
        return LiquidGlassLauncherModel(
            settingsStore: SettingsStore(fileURL: directory.appendingPathComponent("settings.json")),
            inclusionStore: InclusionStore(fileURL: directory.appendingPathComponent("inclusions.json")),
            exclusionStore: exclusions ?? ExclusionStore(fileURL: directory.appendingPathComponent("exclusions.json")),
            calculationHistoryStore: CalculationHistoryStore(fileURL: directory.appendingPathComponent("history.json")),
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: directory.appendingPathComponent("dictionary.json")),
            applicationIndexSnapshotCache: cache,
            applicationIndexLoader: { _ in live }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(condition(), "Expected application state was not published")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucky-application-performance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func item(_ title: String) -> LaunchItem {
        let url = URL(fileURLWithPath: "/Applications/\(title).app")
        return LaunchItem(title: title, subtitle: url.path, url: url, searchText: normalized(title))
    }
}
