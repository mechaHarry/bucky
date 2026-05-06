import XCTest
@testable import Bucky

final class FileBrowserStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyFileBrowserStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        fileURL = temporaryDirectory.appendingPathComponent("file-browser.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testMissingFileLoadsDefaultState() {
        let store = FileBrowserStore(fileURL: fileURL)

        XCTAssertEqual(store.state, .defaultValue)
    }

    func testInvalidJSONFallsBackToDefaultState() throws {
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = FileBrowserStore(fileURL: fileURL)

        XCTAssertEqual(store.state, .defaultValue)
    }

    func testSaveAndReloadPersistsPinsLastDirectorySortTraversalChainAndRememberedSelections() {
        let store = FileBrowserStore(fileURL: fileURL)
        let bookmarkData = Data([1, 2, 3, 4])
        let state = FileBrowserPersistedState(
            pinnedDirectories: [URL(fileURLWithPath: "/Users/test")],
            lastDirectory: URL(fileURLWithPath: "/Users/test/Projects"),
            sort: .dateModified,
            traversalChain: [URL(fileURLWithPath: "/Users"), URL(fileURLWithPath: "/Users/test")],
            rememberedSelections: [
                FileBrowserRememberedSelection(
                    directory: URL(fileURLWithPath: "/Users/test/Projects"),
                    selection: URL(fileURLWithPath: "/Users/test/Projects/README.md")
                )
            ],
            directoryBookmarks: [
                FileBrowserDirectoryBookmark(
                    directory: URL(fileURLWithPath: "/Users/test/Projects"),
                    bookmarkData: bookmarkData
                )
            ]
        )

        store.update(state)

        let reloaded = FileBrowserStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.state, state)
        XCTAssertEqual(
            reloaded.bookmarkData(for: URL(fileURLWithPath: "/Users/test/Projects")),
            bookmarkData
        )
    }
}
