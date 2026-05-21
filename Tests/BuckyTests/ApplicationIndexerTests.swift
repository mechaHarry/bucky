import XCTest
@testable import Bucky

final class ApplicationIndexerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyApplicationIndexerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testDefaultRootsIncludeCoreServicesForNativeSystemApps() {
        XCTAssertTrue(
            ApplicationIndexer.defaultRoots.contains(URL(
                fileURLWithPath: "/System/Library/CoreServices",
                isDirectory: true
            ))
        )
    }

    func testLoadsAppsFromCoreServicesRoot() throws {
        let coreServicesRoot = temporaryDirectory.appendingPathComponent("CoreServices", isDirectory: true)
        let screenSaverURL = try writeApp(
            named: "ScreenSaverEngine.app",
            bundleIdentifier: "com.apple.ScreenSaver.Engine",
            displayName: "Screen Saver",
            under: coreServicesRoot
        )

        let items = ApplicationIndexer(
            roots: [coreServicesRoot],
            systemSettingsItemsProvider: { [] }
        ).load(includedPaths: [])

        XCTAssertEqual(items.map(\.title), ["Screen Saver"])
        XCTAssertEqual(items.first?.url.standardizedFileURL.path, screenSaverURL.standardizedFileURL.path)
        XCTAssertEqual(items.first?.category, .app)
        XCTAssertEqual(items.first?.searchText, "screen saver")
    }

    func testCoreServicesScanDoesNotWalkNestedSupportTrees() throws {
        let coreServicesRoot = temporaryDirectory.appendingPathComponent("CoreServices", isDirectory: true)
        _ = try writeApp(
            named: "ScreenSaverEngine.app",
            bundleIdentifier: "com.apple.ScreenSaver.Engine",
            displayName: "Screen Saver",
            under: coreServicesRoot
        )
        _ = try writeApp(
            named: "Nested Helper.app",
            bundleIdentifier: "com.example.NestedHelper",
            displayName: "Nested Helper",
            under: coreServicesRoot.appendingPathComponent("PrivateSupport", isDirectory: true)
        )

        let items = ApplicationIndexer(
            roots: [coreServicesRoot],
            systemSettingsItemsProvider: { [] }
        ).load(includedPaths: [])

        XCTAssertEqual(items.map(\.title), ["Screen Saver"])
    }

    func testAppendsCustomActionsAfterAppsAndSettings() throws {
        let action = CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Build Docs",
            command: "make docs"
        )

        let items = ApplicationIndexer(
            roots: [],
            systemSettingsItemsProvider: { [] },
            customActionsProvider: { [action] }
        ).load(includedPaths: [])

        XCTAssertEqual(items.map(\.title), ["Build Docs"])
        XCTAssertEqual(items.first?.category, .action)
        XCTAssertEqual(items.first?.launchTarget, .shellCommand("make docs"))
    }

    private func writeApp(
        named name: String,
        bundleIdentifier: String,
        displayName: String,
        under root: URL
    ) throws -> URL {
        let contentsURL = root
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": displayName,
            "CFBundleName": displayName
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return contentsURL.deletingLastPathComponent()
    }
}
