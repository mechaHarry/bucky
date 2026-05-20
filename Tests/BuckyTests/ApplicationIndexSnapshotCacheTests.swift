import XCTest
@testable import Bucky

final class ApplicationIndexSnapshotCacheTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyApplicationIndexSnapshotCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSavesAndLoadsLaunchItems() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("snapshot.json")
        let cache = ApplicationIndexSnapshotCache(fileURL: fileURL)
        let items = [
            LaunchItem(
                title: "Screen Saver",
                subtitle: "/System/Library/CoreServices/ScreenSaverEngine.app",
                url: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"),
                searchText: "screen saver"
            ),
            LaunchItem(
                title: "Wallpaper",
                subtitle: "System Settings",
                url: URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/Wallpaper.appex"),
                launchTarget: .url(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!),
                category: .settings,
                searchText: "wallpaper system settings"
            )
        ]

        cache.save(items)

        XCTAssertEqual(cache.load(), items)
    }

    func testMalformedSnapshotLoadsEmpty() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("snapshot.json")
        try Data("not json".utf8).write(to: fileURL)

        XCTAssertEqual(ApplicationIndexSnapshotCache(fileURL: fileURL).load(), [])
    }
}
