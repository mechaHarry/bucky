import XCTest
@testable import Bucky

@available(macOS 26.0, *)
final class LiquidGlassLauncherFilterTests: XCTestCase {
    func testBlankQueryReturnsEveryVisibleItemInSourceOrder() {
        let items = (0..<90).map { index in
            launchItem(title: "App \(index)", searchText: "app \(index)")
        }

        let results = LiquidGlassLauncherModel.filter(items, normalizedQuery: "")

        XCTAssertEqual(results.count, 90)
        XCTAssertEqual(results.first?.title, "App 0")
        XCTAssertEqual(results.last?.title, "App 89")
    }

    func testQueryRequiresAllTokensAndUsesTitleOrderingForScoreTies() {
        let items = [
            launchItem(title: "Notes Archive", searchText: "notes archive"),
            launchItem(title: "Archive Notes", searchText: "archive notes"),
            launchItem(title: "Notebook Archive", searchText: "notebook archive"),
            launchItem(title: "Notes", searchText: "notes")
        ]

        let results = LiquidGlassLauncherModel.filter(items, normalizedQuery: "not ar")

        XCTAssertEqual(results.map(\.title), [
            "Archive Notes",
            "Notes Archive",
            "Notebook Archive"
        ])
    }

    func testApplicationIconPreloadPolicyWarmsVisibleViewportFirst() {
        let items = (0..<80).map { index in
            launchItem(title: "App \(index)", searchText: "app \(index)")
        }

        let urls = AppIconPreloadPolicy.preloadURLs(for: items)

        XCTAssertEqual(urls.count, 80)
        XCTAssertEqual(urls.last?.lastPathComponent, "App 79.app")
        XCTAssertGreaterThan(AppIconPreloadPolicy.preloadLimit, AppIconPreloadPolicy.initialVisibleLimit)
        XCTAssertLessThan(AppIconPreloadPolicy.initialVisibleLimit, 80)
        XCTAssertGreaterThan(AppIconPreloadPolicy.tailDelayNanoseconds, 0)
    }

    func testApplicationIconPreloadPolicyCapsLargeResultSets() {
        let items = (0..<600).map { index in
            launchItem(title: "App \(index)", searchText: "app \(index)")
        }

        XCTAssertEqual(AppIconPreloadPolicy.preloadURLs(for: items).count, AppIconPreloadPolicy.preloadLimit)
        XCTAssertEqual(AppIconPreloadPolicy.initialDelayNanoseconds, 0)
        XCTAssertGreaterThan(AppIconPreloadPolicy.tailDelayNanoseconds, 0)
        XCTAssertTrue(AppIconPreloadPolicy.shouldYield(afterLoadingItemAt: 7))
        XCTAssertFalse(AppIconPreloadPolicy.shouldYield(afterLoadingItemAt: 6))
    }

    func testReindexDoesNotAdvanceStoreGenerationForUnchangedSnapshots() {
        var store = ApplicationRowStore()
        let finder = launchItem(title: "Finder", searchText: "finder")

        XCTAssertTrue(store.replaceAllIfChanged([finder]))
        let initialGeneration = store.generation

        XCTAssertFalse(store.replaceAllIfChanged([finder]))
        XCTAssertEqual(store.generation, initialGeneration)
    }

    func testApplicationRowStoreReusesStableIDsAcrossSnapshotRefreshes() {
        var store = ApplicationRowStore()
        let finder = launchItem(title: "Finder", searchText: "finder")

        store.replaceAll([finder])
        let originalID = store.allIDs[0]

        store.replaceAll([finder])

        XCTAssertEqual(store.allIDs, [originalID])
        XCTAssertEqual(store.item(for: originalID)?.title, "Finder")
    }

    private func launchItem(title: String, searchText: String) -> LaunchItem {
        LaunchItem(
            title: title,
            subtitle: "/Applications/\(title).app",
            url: URL(fileURLWithPath: "/Applications/\(title).app"),
            searchText: searchText
        )
    }
}
