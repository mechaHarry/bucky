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

    func testSaveAndReloadPersistsPinsLastDirectorySortFoldersFirstTraversalChainAndRememberedSelections() {
        let store = FileBrowserStore(fileURL: fileURL)
        let bookmarkData = Data([1, 2, 3, 4])
        let state = FileBrowserPersistedState(
            pinnedDirectories: [URL(fileURLWithPath: "/Users/harriche")],
            lastDirectory: URL(fileURLWithPath: "/Users/harriche/Projects"),
            sort: .dateModified,
            foldersFirst: true,
            traversalChain: [URL(fileURLWithPath: "/Users"), URL(fileURLWithPath: "/Users/harriche")],
            rememberedSelections: [
                FileBrowserRememberedSelection(
                    directory: URL(fileURLWithPath: "/Users/harriche/Projects"),
                    selection: URL(fileURLWithPath: "/Users/harriche/Projects/README.md")
                )
            ],
            directoryBookmarks: [
                FileBrowserDirectoryBookmark(
                    directory: URL(fileURLWithPath: "/Users/harriche/Projects"),
                    bookmarkData: bookmarkData
                )
            ]
        )

        store.update(state)

        let reloaded = FileBrowserStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.state, state)
        XCTAssertEqual(
            reloaded.bookmarkData(for: URL(fileURLWithPath: "/Users/harriche/Projects")),
            bookmarkData
        )
    }
}
