import XCTest
@testable import Bucky

@MainActor
final class FileBrowserModelTests: XCTestCase {
    func testStartsAtPersistedDirectoryWhenAvailable() {
        let directory = URL(fileURLWithPath: "/Users/test")
        let model = makeModel(persisted: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: directory,
            sort: .name,
            traversalChain: []
        ))

        XCTAssertEqual(model.currentDirectory, directory)
        XCTAssertEqual(model.sort, .name)
    }

    func testStartsAtHomeWhenPersistedDirectoryIsMissing() {
        let model = makeModel(persisted: .defaultValue, home: URL(fileURLWithPath: "/Users/test"))

        XCTAssertEqual(model.currentDirectory, URL(fileURLWithPath: "/Users/test"))
    }

    func testMoveSelectionClampsToEntryBounds() {
        let model = makeModel(entries: entries(["a.txt", "b.txt", "c.txt"]))

        model.handle(.down)
        model.handle(.down)
        model.handle(.down)
        XCTAssertEqual(model.selectedEntry?.name, "c.txt")

        model.handle(.up)
        XCTAssertEqual(model.selectedEntry?.name, "b.txt")
    }

    func testFirstCharacterCyclingMovesBetweenMatchingRows() {
        let model = makeModel(entries: entries(["alpha.txt", "beta.txt", "build.log", "gamma.txt"]))

        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "beta.txt")
        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "build.log")
    }

    func testSpaceTogglesSelectionAndShiftSpaceSelectsRange() {
        let model = makeModel(entries: entries(["one.txt", "two.txt", "three.txt", "four.txt"]))

        model.handle(.space)
        model.handle(.down)
        model.handle(.down)
        model.handle(.shiftSpace)

        XCTAssertEqual(model.selectedURLs.map(\.lastPathComponent), ["one.txt", "two.txt", "three.txt"])
    }

    func testRightOnFileSetsPaneWobble() {
        let model = makeModel(entries: entries(["file.txt"]))

        model.handle(.right)

        XCTAssertEqual(model.wobbleReason, .cannotEnterFile)
    }

    func testShiftSpaceAfterDirectoryChangeUsesOnlyCurrentDirectoryEntries() {
        let home = URL(fileURLWithPath: "/Users/test")
        let childDirectory = home.appendingPathComponent("child", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [
            home: entries(["alpha.txt", "beta.txt", "gamma.txt", "child/"], in: home),
            childDirectory: entries(["only.txt"], in: childDirectory)
        ])

        model.handle(.down)
        model.handle(.down)
        model.handle(.space)
        model.handle(.down)
        model.handle(.right)
        model.handle(.shiftSpace)

        XCTAssertEqual(model.currentDirectory, childDirectory)
        XCTAssertEqual(model.selectedURLs.map(\.lastPathComponent), ["only.txt"])
    }

    private func makeModel(
        entries: [FileBrowserEntry] = [],
        persisted: FileBrowserPersistedState = .defaultValue,
        home: URL = URL(fileURLWithPath: "/Users/test")
    ) -> FileBrowserModel {
        let client = StubFileSystemClient(home: home, entriesByDirectory: [home: entries])
        let store = InMemoryFileBrowserStore(state: persisted)
        return FileBrowserModel(fileSystem: client, store: store)
    }

    private func makeModel(
        persisted: FileBrowserPersistedState = .defaultValue,
        home: URL = URL(fileURLWithPath: "/Users/test"),
        entriesByDirectory: [URL: [FileBrowserEntry]]
    ) -> FileBrowserModel {
        let client = StubFileSystemClient(home: home, entriesByDirectory: entriesByDirectory)
        let store = InMemoryFileBrowserStore(state: persisted)
        return FileBrowserModel(fileSystem: client, store: store)
    }

    private func entries(_ names: [String]) -> [FileBrowserEntry] {
        entries(names, in: URL(fileURLWithPath: "/Users/test"))
    }

    private func entries(_ names: [String], in directory: URL) -> [FileBrowserEntry] {
        names.map { name in
            FileBrowserEntry(
                url: directory.appendingPathComponent(name),
                kind: name.hasSuffix("/") ? .directory : .file,
                size: 1,
                createdAt: nil,
                modifiedAt: nil,
                isHidden: name.hasPrefix(".")
            )
        }
    }
}

private struct StubFileSystemClient: FileSystemClientProtocol {
    let home: URL
    var entriesByDirectory: [URL: [FileBrowserEntry]]

    func homeDirectory() -> URL { home }

    func parentURL(for url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        entriesByDirectory[directory] ?? []
    }
}

private final class InMemoryFileBrowserStore: FileBrowserPersisting {
    private(set) var state: FileBrowserPersistedState

    init(state: FileBrowserPersistedState) {
        self.state = state
    }

    func update(_ nextState: FileBrowserPersistedState) {
        state = nextState
    }
}
