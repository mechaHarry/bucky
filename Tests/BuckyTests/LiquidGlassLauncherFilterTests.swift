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

    func testApplicationRowsStayLazyForModeSwitchInteractivity() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        let resultList = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherResultListView.swift")

        XCTAssertTrue(launcher.contains("resultScrollView(reconstructionID: applicationsReconstructionIdentity)"))
        XCTAssertFalse(launcher.contains("resultScrollView(reconstructionID: applicationsReconstructionIdentity, usesEagerRows: true)"))
        XCTAssertTrue(resultList.contains("let usesEagerRows: Bool"))
        XCTAssertTrue(resultList.contains("LazyVStack(spacing: LauncherResultListLayoutPolicy.rowSpacing)"))
    }

    func testReindexDoesNotClearFilterCacheForUnchangedSnapshots() throws {
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")

        XCTAssertTrue(model.contains("let previousItems = indexedItems"))
        XCTAssertTrue(model.contains("if appRowStore.replaceAllIfChanged(items) {\n                rebuildVisibleItems()\n            }"))
    }

    func testApplicationRowsRenderFromStableRowIDs() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")

        XCTAssertTrue(model.contains("@Published var filteredItemIDs: [AppRowID] = []"))
        XCTAssertTrue(launcher.contains("ForEach(Array(model.filteredItemIDs.enumerated()), id: \\.element)"))
        XCTAssertTrue(launcher.contains("if let item = model.item(for: id)"))
        XCTAssertFalse(launcher.contains("ForEach(Array(model.filteredItems.enumerated()), id: \\.element.url)"))
    }

    func testApplicationsAndToolsUseSharedAppsResultRowAdapters() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(launcher.contains("LauncherAppsResultRow("))
        XCTAssertTrue(launcher.contains("private func applicationRow"))
        XCTAssertTrue(launcher.contains("private func toolRow"))
        XCTAssertTrue(launcher.contains("ResultRowID.application(id)"))
        XCTAssertTrue(launcher.contains("ResultRowID.tool(item)"))
        XCTAssertFalse(launcher.contains("verticalPadding: 11"))
        XCTAssertFalse(launcher.contains("ToolItem(item)"))
    }

    func testDictionaryRouteRendersAndScrollsSharedToolRows() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertGreaterThanOrEqual(
            launcher.components(separatedBy: "model.isApplicationToolActive").count - 1,
            2
        )
        XCTAssertFalse(launcher.contains("if model.isApplicationCalculatorActive {\n                        resultScrollView(reconstructionID: toolResultsSnapshotIdentity)"))
    }

    func testDictionaryLoadingRendersSharedSkeletonRowsBeforeStaleResults() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(launcher.contains("model.isDictionaryLookupLoading"))
        XCTAssertTrue(launcher.contains("LauncherAppsResultSkeletonRow"))
        XCTAssertTrue(launcher.contains("ForEach(0..<4"))
        XCTAssertTrue(launcher.contains("else if let emptyMessage = model.emptyMessage"))
    }

    func testApplicationIndexSnapshotMemoizationIsWiredOffMainThread() throws {
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")

        XCTAssertTrue(model.contains("loadCachedApplicationSnapshot()"))
        XCTAssertTrue(model.contains("DispatchQueue.global(qos: .utility).async { [applicationIndexSnapshotCache] in"))
        XCTAssertTrue(model.contains("applicationIndexSnapshotCache.load()"))
        XCTAssertTrue(model.contains("applicationIndexSnapshotCache.save(items)"))
    }

    func testWarmFilterCacheWritesAreGenerationScoped() throws {
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")

        XCTAssertTrue(model.contains("generation: Int"))
        XCTAssertTrue(model.contains("self?.storeWarmFilterEntries(entries, generation: snapshot.generation)"))
        XCTAssertTrue(model.contains("filterCache.store(entry.results, for: entry.query, generation: generation)"))
    }

    private func launchItem(title: String, searchText: String) -> LaunchItem {
        LaunchItem(
            title: title,
            subtitle: "/Applications/\(title).app",
            url: URL(fileURLWithPath: "/Applications/\(title).app"),
            searchText: searchText
        )
    }

    private func source(named path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
