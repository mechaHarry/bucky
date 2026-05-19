import XCTest
@testable import Bucky

@available(macOS 26.0, *)
final class LiquidGlassLauncherFilterTests: XCTestCase {
    func testBlankQueryReturnsFirstEightyItemsInSourceOrder() {
        let items = (0..<90).map { index in
            launchItem(title: "App \(index)", searchText: "app \(index)")
        }

        let results = LiquidGlassLauncherModel.filter(items, normalizedQuery: "")

        XCTAssertEqual(results.count, 80)
        XCTAssertEqual(results.first?.title, "App 0")
        XCTAssertEqual(results.last?.title, "App 79")
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

    func testApplicationIconPreloadPolicyWarmsBeyondFirstViewport() {
        let items = (0..<80).map { index in
            launchItem(title: "App \(index)", searchText: "app \(index)")
        }

        let urls = AppIconPreloadPolicy.preloadURLs(for: items)

        XCTAssertEqual(urls.count, 80)
        XCTAssertEqual(urls.last?.lastPathComponent, "App 79.app")
        XCTAssertGreaterThan(AppIconPreloadPolicy.preloadLimit, AppIconPreloadPolicy.initialVisibleLimit)
    }

    func testApplicationIconPreloadPolicyCapsLargeResultSets() {
        let items = (0..<600).map { index in
            launchItem(title: "App \(index)", searchText: "app \(index)")
        }

        XCTAssertEqual(AppIconPreloadPolicy.preloadURLs(for: items).count, AppIconPreloadPolicy.preloadLimit)
        XCTAssertTrue(AppIconPreloadPolicy.shouldYield(afterLoadingItemAt: 15))
        XCTAssertFalse(AppIconPreloadPolicy.shouldYield(afterLoadingItemAt: 14))
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
