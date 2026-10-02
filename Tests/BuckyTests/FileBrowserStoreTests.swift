import XCTest
@testable import Bucky

private final class FailingFilesPersistenceManager: FileManager, @unchecked Sendable {
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        isDirectory?.pointee = false
        return true
    }
}

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
        XCTAssertTrue(store.canWrite)
        XCTAssertNil(store.persistenceError)
    }

    @MainActor
    func testConcurrentBookmarkReadsRemainConsistentDuringPreferenceUpdates() async {
        let store = FileBrowserStore(fileURL: fileURL)
        let directory = URL(fileURLWithPath: "/tmp/bookmark-fixture", isDirectory: true)
        let bookmark = FileBrowserDirectoryBookmark(directory: directory, bookmarkData: Data([1, 2, 3]))
        var initial = FileBrowserPersistedState.defaultValue
        initial.directoryBookmarks = [bookmark]
        store.update(initial)
        let reader = Task.detached {
            (0..<1_000).allSatisfy { _ in store.bookmarkData(for: directory) == bookmark.bookmarkData }
        }
        for index in 0..<100 {
            var next = initial
            next.foldersFirst = index.isMultiple(of: 2)
            store.update(next)
        }
        let consistent = await reader.value
        XCTAssertTrue(consistent)
        await withCheckedContinuation { continuation in store.flush { continuation.resume() } }
        XCTAssertEqual(FileBrowserStore(fileURL: fileURL).bookmarkData(for: directory), bookmark.bookmarkData)
    }

    @MainActor
    func testUnreadablePreferencesArePreservedAndCannotBeWritten() async throws {
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let sentinel = fileURL.appendingPathComponent("sentinel.txt")
        try "sentinel".write(to: sentinel, atomically: true, encoding: .utf8)
        let store = FileBrowserStore(fileURL: fileURL)
        XCTAssertFalse(store.canWrite)
        XCTAssertNotNil(store.persistenceError)
        store.update(.defaultValue)
        await withCheckedContinuation { continuation in store.flush { continuation.resume() } }
        XCTAssertEqual(try String(contentsOf: sentinel), "sentinel")
    }

    @MainActor
    func testBackgroundSaveUsesPrivateFileAndNewDirectoryPermissions() async throws {
        let privateDirectory = temporaryDirectory.appendingPathComponent("Private", isDirectory: true)
        let url = privateDirectory.appendingPathComponent("state.json")
        let store = FileBrowserStore(fileURL: url)
        store.update(.defaultValue)
        await withCheckedContinuation { continuation in store.flush { continuation.resume() } }
        let directoryMode = try FileManager.default.attributesOfItem(atPath: privateDirectory.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        XCTAssertEqual(fileMode?.intValue, 0o600)
    }

    @MainActor
    func testInvalidJSONIsPreservedAndDisablesAutosave() async throws {
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = FileBrowserStore(fileURL: fileURL)

        XCTAssertEqual(store.state, .defaultValue)
        XCTAssertFalse(store.canWrite)
        XCTAssertNotNil(store.persistenceError)
        var state = FileBrowserPersistedState.defaultValue
        state.pinnedDirectories = [URL(fileURLWithPath: "/tmp/fixture-pin", isDirectory: true)]
        store.update(state)
        await withCheckedContinuation { continuation in store.flush { continuation.resume() } }
        XCTAssertEqual(try String(contentsOf: fileURL), "not json")
        XCTAssertEqual(store.state, .defaultValue)
    }

    @MainActor
    func testBackgroundPersistenceKeepsLatestUpdateAndReportsFailure() async throws {
        let store = FileBrowserStore(fileURL: fileURL)
        for index in 0..<50 {
            var state = FileBrowserPersistedState.defaultValue
            state.lastDirectory = URL(fileURLWithPath: "/tmp/folder-\(index)", isDirectory: true)
            store.update(state)
        }
        await withCheckedContinuation { continuation in store.flush { continuation.resume() } }
        XCTAssertEqual(FileBrowserStore(fileURL: fileURL).state.lastDirectory?.lastPathComponent, "folder-49")

        let failedStore = FileBrowserStore(fileURL: fileURL, fileManager: FailingFilesPersistenceManager())
        let originalState = failedStore.state
        let error = expectation(description: "visible persistence failure")
        failedStore.onPersistenceError = { message in
            XCTAssertEqual(message, "Could not save Files preferences.")
            XCTAssertTrue(Thread.isMainThread)
            error.fulfill()
        }
        failedStore.update(.defaultValue)
        await fulfillment(of: [error], timeout: 2)
        await withCheckedContinuation { continuation in failedStore.flush { continuation.resume() } }
        XCTAssertEqual(failedStore.persistenceError, "Could not save Files preferences.")
        XCTAssertEqual(failedStore.state, originalState)
        XCTAssertEqual(FileBrowserStore(fileURL: fileURL).state, originalState)
    }

    func testRetentionBoundsSelectionsTraversalAndBookmarksWithoutEvictingPinAccess() {
        let directories = (0..<500).map { URL(fileURLWithPath: "/tmp/folder-\($0)", isDirectory: true) }
        let state = FileBrowserPersistedState(
            pinnedDirectories: [directories[0]], lastDirectory: directories.last, sort: .name,
            traversalChain: directories,
            rememberedSelections: directories.map { FileBrowserRememberedSelection(directory: $0, selection: $0.appendingPathComponent("sample.txt")) },
            directoryBookmarks: directories.map { FileBrowserDirectoryBookmark(directory: $0, bookmarkData: Data([1])) }
        )
        let bounded = FileBrowserRetentionPolicy.bounded(state)
        XCTAssertEqual(bounded.traversalChain.count, FileBrowserRetentionPolicy.historyLimit)
        XCTAssertEqual(bounded.rememberedSelections.count, FileBrowserRetentionPolicy.selectionLimit)
        XCTAssertEqual(bounded.directoryBookmarks.count, FileBrowserRetentionPolicy.bookmarkLimit)
        XCTAssertTrue(bounded.directoryBookmarks.contains { $0.directory == directories[0] })
        XCTAssertTrue(bounded.directoryBookmarks.contains { $0.directory == directories.last })
        XCTAssertEqual(bounded.pinnedDirectories, state.pinnedDirectories)
    }

    func testSaveAndReloadPersistsPinsLastDirectorySortFoldersFirstTraversalChainAndRememberedSelections() async {
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
        await withCheckedContinuation { continuation in
            store.flush { continuation.resume() }
        }

        let reloaded = FileBrowserStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.state, state)
        XCTAssertEqual(
            reloaded.bookmarkData(for: projectsDirectory),
            bookmarkData
        )
    }
}
