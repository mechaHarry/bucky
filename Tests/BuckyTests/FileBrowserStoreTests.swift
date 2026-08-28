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
        let projectsDirectory = TestFixtures.userHome.appendingPathComponent("Projects", isDirectory: true)
        let state = FileBrowserPersistedState(
            pinnedDirectories: [TestFixtures.userHome],
            lastDirectory: projectsDirectory,
            sort: .dateModified,
            foldersFirst: true,
            traversalChain: [TestFixtures.userRoot, TestFixtures.userHome],
            rememberedSelections: [
                FileBrowserRememberedSelection(
                    directory: projectsDirectory,
                    selection: projectsDirectory.appendingPathComponent("README.md")
                )
            ],
            directoryBookmarks: [
                FileBrowserDirectoryBookmark(
                    directory: projectsDirectory,
                    bookmarkData: bookmarkData
                )
            ]
        )

        store.update(state)

        let reloaded = FileBrowserStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.state, state)
        XCTAssertEqual(
            reloaded.bookmarkData(for: projectsDirectory),
            bookmarkData
        )
    }
}
