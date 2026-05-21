import XCTest
@testable import Bucky

final class SystemSettingsIndexerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckySystemSettingsIndexerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testLoadsTopLevelSystemSettingsPanesFromSidebarAndMatchingExtensions() throws {
        let sidebarURL = temporaryDirectory.appendingPathComponent("Sidebar.plist")
        try writePropertyList(
            [
                ["content": [
                    "com.apple.Displays-Settings.extension",
                    "com.apple.Wallpaper-Settings.extension",
                    "com.apple.Hidden-Settings.extension"
                ]]
            ],
            to: sidebarURL
        )

        let extensionsRoot = temporaryDirectory.appendingPathComponent("Extensions", isDirectory: true)
        try writeExtension(
            bundleDirectoryName: "DisplaysExt.appex",
            bundleIdentifier: "com.apple.Displays-Settings.extension",
            displayName: "Displays",
            allowsSystemPreferencesURL: true,
            under: extensionsRoot
        )
        try writeExtension(
            bundleDirectoryName: "Wallpaper.appex",
            bundleIdentifier: "com.apple.Wallpaper-Settings.extension",
            displayName: "Wallpaper",
            allowsSystemPreferencesURL: true,
            under: extensionsRoot
        )
        try writeExtension(
            bundleDirectoryName: "Hidden.appex",
            bundleIdentifier: "com.apple.Hidden-Settings.extension",
            displayName: "Hidden",
            allowsSystemPreferencesURL: false,
            under: extensionsRoot
        )

        let items = SystemSettingsIndexer(
            sidebarURL: sidebarURL,
            extensionRoots: [extensionsRoot]
        ).load()

        XCTAssertEqual(items.map(\.title), ["Displays", "Wallpaper"])
        XCTAssertEqual(items.map(\.subtitle), ["System Settings", "System Settings"])
        XCTAssertEqual(items.map(\.category), [.settings, .settings])
        XCTAssertEqual(
            items.map(\.launchTarget),
            [
                .url(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!),
                .url(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
            ]
        )
        XCTAssertEqual(items.map(\.searchText), ["displays system settings", "wallpaper system settings"])
    }

    func testDoesNotCreateDeepSectionItemsFromSearchTermsFiles() throws {
        let sidebarURL = temporaryDirectory.appendingPathComponent("Sidebar.plist")
        try writePropertyList(
            [["content": ["com.apple.Displays-Settings.extension"]]],
            to: sidebarURL
        )

        let extensionsRoot = temporaryDirectory.appendingPathComponent("Extensions", isDirectory: true)
        let extensionURL = try writeExtension(
            bundleDirectoryName: "DisplaysExt.appex",
            bundleIdentifier: "com.apple.Displays-Settings.extension",
            displayName: "Displays",
            allowsSystemPreferencesURL: true,
            under: extensionsRoot
        )
        let searchTermsURL = extensionURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: searchTermsURL, withIntermediateDirectories: true)
        try writePropertyList(
            [
                "nightShiftSection": [
                    "localizableStrings": [
                        ["title": "Night Shift options", "index": "warm color"]
                    ]
                ]
            ],
            to: searchTermsURL.appendingPathComponent("DisplaysSearchGroups.searchTerms")
        )

        let items = SystemSettingsIndexer(
            sidebarURL: sidebarURL,
            extensionRoots: [extensionsRoot]
        ).load()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Displays")
        XCTAssertFalse(items.contains { $0.title == "Night Shift options" })
    }

    func testApplicationLaunchItemsDefaultToAppCategory() {
        let url = URL(fileURLWithPath: "/Applications/Notes.app")

        let item = LaunchItem(
            title: "Notes",
            subtitle: url.path,
            url: url,
            searchText: "notes"
        )

        XCTAssertEqual(item.category, .app)
        XCTAssertEqual(LaunchItemCategory.app.title, "App")
        XCTAssertEqual(LaunchItemCategory.settings.title, "Settings")
        XCTAssertEqual(LaunchItemCategory.action.title, "Action")
    }

    @discardableResult
    private func writeExtension(
        bundleDirectoryName: String,
        bundleIdentifier: String,
        displayName: String,
        allowsSystemPreferencesURL: Bool,
        under root: URL
    ) throws -> URL {
        let contentsURL = root
            .appendingPathComponent(bundleDirectoryName, isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        try writePropertyList(
            [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleDisplayName": displayName,
                "EXAppExtensionAttributes": [
                    "SettingsExtensionAttributes": [
                        "allowsXAppleSystemPreferencesURLScheme": allowsSystemPreferencesURL
                    ]
                ]
            ],
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        return contentsURL.deletingLastPathComponent()
    }

    private func writePropertyList(_ propertyList: Any, to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}
