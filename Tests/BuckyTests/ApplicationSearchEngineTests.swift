import XCTest
@testable import Bucky

@available(macOS 26.0, *)
final class ApplicationSearchEngineTests: XCTestCase {
    func testEmptyQueryReturnsInMemoryItemsInSourceOrder() {
        let items = [
            launchItem(title: "Calendar"),
            launchItem(title: "Notes"),
            launchItem(title: "Terminal")
        ]

        let results = ApplicationSearchEngine.filter(items, normalizedQuery: "")

        XCTAssertEqual(results.map(\.title), ["Calendar", "Notes", "Terminal"])
    }

    func testWhitespaceOnlyQueryPreservesPreviousScoredOrdering() {
        let items = [
            launchItem(title: "Long Application"),
            launchItem(title: "App"),
            launchItem(title: "Medium")
        ]
        var rowStore = ApplicationRowStore()
        rowStore.replaceAll(items)

        let rankedItems = ApplicationSearchEngine.filter(items, normalizedQuery: "   ")
        let rankedIDs = ApplicationSearchEngine.filterIDs(
            rowStore.visibleIDs,
            rowStore: rowStore,
            normalizedQuery: "   "
        )

        XCTAssertEqual(rankedItems.map(\.title), ["App", "Medium", "Long Application"])
        XCTAssertEqual(rowStore.items(for: rankedIDs).map(\.title), ["App", "Medium", "Long Application"])
    }

    func testTokenizedQueryIgnoresExtraWhitespace() {
        let tokens = ApplicationSearchEngine.tokens(for: "  notes   ar  ")

        XCTAssertEqual(tokens, ["notes", "ar"])
    }

    func testRankingOrdersExactPrefixWordPrefixSubstringThenSearchTextMatches() {
        let items = [
            launchItem(title: "Metadata Carrier", searchText: "metadata carrier notes"),
            launchItem(title: "MyNotes", searchText: "mynotes"),
            launchItem(title: "Archive Notes", searchText: "archive notes"),
            launchItem(title: "Notes Archive", searchText: "notes archive"),
            launchItem(title: "Notes", searchText: "notes")
        ]

        let results = ApplicationSearchEngine.filter(items, normalizedQuery: "notes")

        XCTAssertEqual(results.map(\.title), [
            "Notes",
            "Notes Archive",
            "Archive Notes",
            "MyNotes",
            "Metadata Carrier"
        ])
    }

    func testQueryRequiresEveryTokenAndUsesDeterministicTitleTies() {
        let items = [
            launchItem(title: "Notes Archive", searchText: "notes archive"),
            launchItem(title: "Archive Notes", searchText: "archive notes"),
            launchItem(title: "Notebook Archive", searchText: "notebook archive"),
            launchItem(title: "Notes", searchText: "notes")
        ]

        let results = ApplicationSearchEngine.filter(items, normalizedQuery: "not ar")

        XCTAssertEqual(results.map(\.title), [
            "Archive Notes",
            "Notes Archive",
            "Notebook Archive"
        ])
    }

    func testEqualTitleTiesKeepOriginalSourceOrderDeterministically() {
        let first = launchItem(title: "Notes", subtitle: "/Applications/First.app", searchText: "notes")
        let second = launchItem(title: "Notes", subtitle: "/Applications/Second.app", searchText: "notes")

        let results = ApplicationSearchEngine.filter([second, first], normalizedQuery: "notes")

        XCTAssertEqual(results.map(\.subtitle), [
            "/Applications/Second.app",
            "/Applications/First.app"
        ])
    }

    func testIndexedAndInMemorySearchProduceEquivalentRanking() {
        let items = [
            launchItem(title: "Notes Archive", searchText: "notes archive"),
            launchItem(title: "Archive Notes", searchText: "archive notes"),
            launchItem(title: "Notebook Archive", searchText: "notebook archive"),
            launchItem(title: "Notes", searchText: "notes")
        ]
        var rowStore = ApplicationRowStore()
        rowStore.replaceAll(items)

        let rankedItems = ApplicationSearchEngine.filter(items, normalizedQuery: "not ar")
        let rankedIDs = ApplicationSearchEngine.filterIDs(
            rowStore.visibleIDs,
            rowStore: rowStore,
            normalizedQuery: "not ar"
        )

        XCTAssertEqual(rowStore.items(for: rankedIDs), rankedItems)
    }

    private func launchItem(
        title: String,
        subtitle: String? = nil,
        searchText: String? = nil
    ) -> LaunchItem {
        let path = subtitle ?? "/Applications/\(title).app"
        return LaunchItem(
            title: title,
            subtitle: path,
            url: URL(fileURLWithPath: path),
            searchText: searchText ?? normalized(title)
        )
    }
}
