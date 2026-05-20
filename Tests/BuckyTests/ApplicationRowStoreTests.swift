import XCTest
@testable import Bucky

final class ApplicationRowStoreTests: XCTestCase {
    func testStoresRowsByStableIDAndPublishesIDLists() {
        var store = ApplicationRowStore()
        let first = launchItem(title: "Finder", path: "/System/Library/CoreServices/Finder.app")
        let second = launchItem(title: "Screen Saver", path: "/System/Library/CoreServices/ScreenSaverEngine.app")

        store.replaceAll([first, second])
        store.rebuildVisibleIDs { $0.title != "Finder" }

        XCTAssertEqual(store.allIDs.count, 2)
        XCTAssertEqual(store.visibleIDs.count, 1)
        XCTAssertEqual(store.item(for: store.visibleIDs[0])?.title, "Screen Saver")
    }

    func testReusesStableIDWhenRowsAreRefreshed() {
        var store = ApplicationRowStore()
        let first = launchItem(title: "Finder", path: "/System/Library/CoreServices/Finder.app")
        store.replaceAll([first])
        let originalID = store.allIDs[0]

        let refreshed = launchItem(title: "Finder", path: "/System/Library/CoreServices/Finder.app")
        store.replaceAll([refreshed])

        XCTAssertEqual(store.allIDs, [originalID])
        XCTAssertEqual(store.item(for: originalID)?.title, "Finder")
    }

    func testSearchCacheStoresRowIDsInsteadOfRows() {
        var cache = ApplicationFilterCache()
        let id = AppRowID(rawValue: 42)

        let results = cache.results(for: "finder", generation: 1) { [id] }

        XCTAssertEqual(results, [id])
        XCTAssertEqual(cache.results(for: "finder", generation: 1) { [] }, [id])
    }

    func testSearchCacheDoesNotReuseResultsAcrossGenerations() {
        var cache = ApplicationFilterCache()
        let oldID = AppRowID(rawValue: 1)
        let newID = AppRowID(rawValue: 2)

        XCTAssertEqual(cache.results(for: "finder", generation: 1) { [oldID] }, [oldID])
        XCTAssertEqual(cache.results(for: "finder", generation: 2) { [newID] }, [newID])
    }

    func testWarmSearchCacheStoresAreGenerationScoped() {
        var cache = ApplicationFilterCache()
        let oldID = AppRowID(rawValue: 1)
        let newID = AppRowID(rawValue: 2)

        cache.store([oldID], for: "screen", generation: 1)
        cache.store([newID], for: "screen", generation: 2)

        XCTAssertEqual(cache.results(for: "screen", generation: 2) { [] }, [newID])
    }

    func testReplacingRowsAdvancesGenerationOnlyWhenSnapshotChanges() {
        var store = ApplicationRowStore()
        let finder = launchItem(title: "Finder", path: "/System/Library/CoreServices/Finder.app")

        XCTAssertEqual(store.generation, 0)
        XCTAssertTrue(store.replaceAllIfChanged([finder]))
        XCTAssertEqual(store.generation, 1)
        XCTAssertFalse(store.replaceAllIfChanged([finder]))
        XCTAssertEqual(store.generation, 1)
    }

    private func launchItem(title: String, path: String) -> LaunchItem {
        LaunchItem(
            title: title,
            subtitle: path,
            url: URL(fileURLWithPath: path),
            searchText: normalized(title)
        )
    }
}
