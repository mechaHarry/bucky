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

    func testActionAvailabilityChangesForSingleAndMultipleSelections() {
        let model = makeModel(entries: entries(["one.txt", "two.txt"]))

        model.handle(.space)
        XCTAssertEqual(model.availableActions, [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash])

        model.handle(.down)
        model.handle(.shiftSpace)
        XCTAssertEqual(model.availableActions, [.batchRename, .copyPaths, .copy, .move, .moveToTrash])
    }

    func testActionOverlayKeyboardSelectionAndReturnStartsFocusedAction() {
        let model = makeModel(entries: entries(["one.txt"]))

        model.handle(.space)
        model.handle(.open)
        model.handle(.down)
        model.handle(.down)
        model.handle(.down)
        model.handle(.open)

        XCTAssertEqual(model.focusState, .transferPending(.copy(model.selectedURLs)))
    }

    func testFocusedActionIndexMatchesFocusableActionsExecutedByReturn() {
        let model = makeModel(entries: entries(["one.txt"]))

        model.handle(.space)
        model.handle(.open)
        model.handle(.down)
        model.handle(.down)
        model.handle(.down)

        XCTAssertEqual(model.focusableActions[model.focusedActionIndex], .copy)

        model.handle(.open)

        XCTAssertEqual(model.focusState, .transferPending(.copy(model.selectedURLs)))
    }

    func testCopyMoveStagePayloadAndEscapeCancelsBackToActions() {
        let model = makeModel(entries: entries(["one.txt"]))

        model.handle(.space)
        model.startTransfer(.copy)
        XCTAssertEqual(model.focusState, .transferPending(.copy(model.selectedURLs)))

        model.handle(.close)
        XCTAssertEqual(model.focusState, .previewActions)
    }

    func testMoveTransferEscapeCancelsBackToActions() {
        let model = makeModel(entries: entries(["one.txt"]))

        model.handle(.space)
        model.startTransfer(.move)
        XCTAssertEqual(model.focusState, .transferPending(.move(model.selectedURLs)))

        model.handle(.close)
        XCTAssertEqual(model.focusState, .previewActions)
    }

    func testReturnDuringTransferAsksForDestinationConfirmation() {
        let model = makeModel(entries: entries(["one.txt"]))

        model.handle(.space)
        model.startTransfer(.move)
        model.handle(.open)

        XCTAssertEqual(model.focusState, .confirming(.transfer(.move(model.selectedURLs), destination: model.currentDirectory)))
    }

    func testMoveToTrashUsesDoubleConfirmState() {
        let model = makeModel(entries: entries(["one.txt"]))

        model.handle(.space)
        model.requestTrashConfirmation()

        XCTAssertEqual(model.focusState, .confirming(.trash(model.selectedURLs, step: 1)))
        model.confirmTrashStep()
        XCTAssertEqual(model.focusState, .confirming(.trash(model.selectedURLs, step: 2)))
        model.confirmTrashStep()
        XCTAssertEqual(model.focusState, .confirming(.trash(model.selectedURLs, step: 2)))
    }

    func testPinsPersist() {
        let home = URL(fileURLWithPath: "/Users/test")
        let client = StubFileSystemClient(home: home, entriesByDirectory: [home: []])
        let store = InMemoryFileBrowserStore(state: .defaultValue)
        let model = FileBrowserModel(fileSystem: client, store: store)
        let pin = URL(fileURLWithPath: "/Users/test/Projects")

        model.togglePin(pin)

        XCTAssertEqual(model.pinnedDirectories, [pin])
        XCTAssertEqual(store.state.pinnedDirectories, [pin])

        model.togglePin(pin)

        XCTAssertEqual(model.pinnedDirectories, [])
        XCTAssertEqual(store.state.pinnedDirectories, [])
    }

    func testRightRestoresRememberedTraversalChainAfterMovingLeft() {
        let home = URL(fileURLWithPath: "/Users/test")
        let child = home.appendingPathComponent("Projects", isDirectory: true)
        let client = StubFileSystemClient(
            home: home,
            entriesByDirectory: [
                home: [directoryEntry(child)],
                child: []
            ]
        )
        let store = InMemoryFileBrowserStore(state: .defaultValue)
        let model = FileBrowserModel(fileSystem: client, store: store)

        model.handle(.right)
        model.handle(.left)
        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, child)
    }

    func testRightAfterMovingAwayFromRememberedChildUsesSelectedRow() {
        let home = URL(fileURLWithPath: "/Users/test")
        let remembered = home.appendingPathComponent("Projects", isDirectory: true)
        let other = home.appendingPathComponent("Archive", isDirectory: true)
        let client = StubFileSystemClient(
            home: home,
            entriesByDirectory: [
                home: [directoryEntry(remembered), directoryEntry(other)],
                remembered: [],
                other: []
            ]
        )
        let store = InMemoryFileBrowserStore(state: .defaultValue)
        let model = FileBrowserModel(fileSystem: client, store: store)

        model.handle(.right)
        model.handle(.left)
        model.handle(.down)
        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, other)
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

    private func directoryEntry(_ url: URL) -> FileBrowserEntry {
        FileBrowserEntry(url: url, kind: .directory, size: nil, createdAt: nil, modifiedAt: nil, isHidden: false)
    }
}
