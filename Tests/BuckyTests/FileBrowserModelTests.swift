import XCTest
import AppKit
import Combine
@testable import Bucky

@MainActor
final class FileBrowserModelTests: XCTestCase {
    func testStartsAtPersistedDirectoryWhenAvailable() {
        let directory = TestFixtures.userHome
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
        let model = makeModel(persisted: .defaultValue, home: TestFixtures.userHome)

        XCTAssertEqual(model.currentDirectory, TestFixtures.userHome)
    }

    func testStartsAtConfiguredDefaultDirectoryBeforeHomeWhenPersistedDirectoryIsMissing() {
        let home = TestFixtures.userHome
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            documents: entries(["notes.txt"], in: documents)
        ])

        let model = FileBrowserModel(
            fileSystem: client,
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: ImmediateDirectoryStream(fileSystem: client),
            startDirectory: documents
        )

        XCTAssertEqual(model.currentDirectory, documents)
    }

    func testUnreadablePersistedDirectoryFallsBackToHomeAndPersistsFallback() {
        let home = URL(fileURLWithPath: "/Users/test")
        let missing = home.appendingPathComponent("Missing", isDirectory: true)
        let client = ThrowingFileSystemClient(
            home: home,
            entriesByDirectory: [home: entries(["home.txt"], in: home)],
            throwingDirectories: [missing]
        )
        let store = InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: missing,
            sort: .name,
            traversalChain: []
        ))

        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        XCTAssertEqual(model.currentDirectory, home)
        XCTAssertEqual(model.entries.map(\.name), ["home.txt"])
        XCTAssertEqual(model.statusMessage, "failed")
        XCTAssertEqual(store.state.lastDirectory, home)
        XCTAssertEqual(Array(client.entryRequests.map(\.directory).prefix(2)), [missing, home])
    }

    func testCurrentDirectoryLoadsThroughStreamWithLoadingPlaceholderState() {
        let home = URL(fileURLWithPath: "/Users/test")
        let stream = ManualDirectoryStream()
        let model = FileBrowserModel(
            fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: stream
        )

        XCTAssertTrue(model.isLoadingEntries)
        XCTAssertEqual(model.entries, [])
        XCTAssertEqual(model.directorySnapshots, [
            FileBrowserDirectorySnapshot(directory: home, entries: [])
        ])
        XCTAssertEqual(stream.requests.map(requestDescription), ["\(home.path)|name|false"])

        stream.completeRequest(at: 0, with: .success(entries(["home.txt"], in: home)))

        XCTAssertFalse(model.isLoadingEntries)
        XCTAssertEqual(model.entries.map(\.name), ["home.txt"])
        XCTAssertEqual(model.directorySnapshots, [
            FileBrowserDirectorySnapshot(directory: home, entries: entries(["home.txt"], in: home))
        ])
    }

    func testSuccessfulDirectoryLoadRemembersDirectoryAccess() {
        let home = URL(fileURLWithPath: "/Users/test")
        let store = InMemoryFileBrowserStore(state: .defaultValue)
        _ = FileBrowserModel(
            fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [
                home: entries(["home.txt"], in: home)
            ]),
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [
                home: entries(["home.txt"], in: home)
            ]))
        )

        XCTAssertEqual(store.rememberedAccessDirectories, [home])
    }

    func testStaleOlderStreamResultsCannotOverwriteNewerDirectoryRequest() {
        let home = URL(fileURLWithPath: "/Users/test")
        let oldDirectory = home.appendingPathComponent("Old", isDirectory: true)
        let newDirectory = home.appendingPathComponent("New", isDirectory: true)
        let stream = ManualDirectoryStream()
        let model = FileBrowserModel(
            fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: stream
        )

        stream.completeRequest(at: 0, with: .success([
            directoryEntry(oldDirectory),
            directoryEntry(newDirectory)
        ]))

        model.openPinnedDirectory(oldDirectory)
        let oldRequestIndex = stream.requests.count - 1
        XCTAssertEqual(model.currentDirectory, oldDirectory)
        XCTAssertTrue(model.isLoadingEntries)

        model.openPinnedDirectory(newDirectory)
        let newRequestIndex = stream.requests.count - 1
        XCTAssertEqual(model.currentDirectory, newDirectory)
        XCTAssertTrue(model.isLoadingEntries)

        stream.completeRequest(at: oldRequestIndex, with: .success(entries(["stale.txt"], in: oldDirectory)))
        XCTAssertEqual(model.currentDirectory, newDirectory)
        XCTAssertEqual(model.entries, [])
        XCTAssertTrue(model.isLoadingEntries)

        stream.completeRequest(at: newRequestIndex, with: .success(entries(["fresh.txt"], in: newDirectory)))
        XCTAssertEqual(model.currentDirectory, newDirectory)
        XCTAssertEqual(model.entries.map(\.name), ["fresh.txt"])
        XCTAssertFalse(model.isLoadingEntries)
    }

    func testHighlightingDirectoryDoesNotLoadChildDirectoryEntries() {
        let home = URL(fileURLWithPath: "/")
        let archive = home.appendingPathComponent("Archive", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let stream = ManualDirectoryStream()
        let model = FileBrowserModel(
            fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: stream
        )

        stream.completeRequest(at: 0, with: .success([directoryEntry(archive), directoryEntry(projects)]))

        XCTAssertEqual(stream.requests.map(\.directory), [home])

        model.handle(.alphaNumeric("p"))

        XCTAssertEqual(model.selectedEntry?.url, projects)
        XCTAssertEqual(stream.requests.map(\.directory), [home])
    }

    func testUnreadablePersistedDirectoryFallsBackToHomeThroughStream() {
        let home = URL(fileURLWithPath: "/Users/test")
        let missing = home.appendingPathComponent("Missing", isDirectory: true)
        let stream = ManualDirectoryStream()
        let store = InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: missing,
            sort: .name,
            traversalChain: []
        ))
        let model = FileBrowserModel(
            fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
            store: store,
            directoryStream: stream
        )

        XCTAssertEqual(model.currentDirectory, missing)
        XCTAssertTrue(model.isLoadingEntries)

        stream.completeRequest(at: 0, with: .failure(TestFileBrowserServiceError.failed))

        XCTAssertEqual(model.currentDirectory, home)
        XCTAssertTrue(model.isLoadingEntries)
        XCTAssertEqual(stream.requests.map(requestDescription), [
            "\(missing.path)|name|false",
            "\(home.path)|name|false"
        ])

        stream.completeRequest(at: 1, with: .success(entries(["home.txt"], in: home)))

        XCTAssertFalse(model.isLoadingEntries)
        XCTAssertEqual(model.entries.map(\.name), ["home.txt"])
        XCTAssertEqual(model.statusMessage, "failed")
        XCTAssertEqual(store.state.lastDirectory, home)
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

    func testRepeatedSelectionCommandsPublishScrollEventsEvenWhenClamped() {
        let model = makeModel(entries: entries(["a.txt", "b.txt", "c.txt"]))

        model.handle(.down)
        let downEvent = model.selectionScrollEvent
        XCTAssertEqual(downEvent?.url.lastPathComponent, "b.txt")
        XCTAssertEqual(downEvent?.anchor, .nearest)

        model.handle(.up)
        let topEvent = model.selectionScrollEvent
        XCTAssertEqual(topEvent?.url.lastPathComponent, "a.txt")
        XCTAssertEqual(topEvent?.anchor, .nearest)
        XCTAssertGreaterThan(topEvent?.id ?? 0, downEvent?.id ?? 0)

        model.handle(.up)
        let clampedTopEvent = model.selectionScrollEvent
        XCTAssertEqual(model.selectedEntry?.name, "a.txt")
        XCTAssertEqual(clampedTopEvent?.url.lastPathComponent, "a.txt")
        XCTAssertEqual(clampedTopEvent?.anchor, .nearest)
        XCTAssertGreaterThan(clampedTopEvent?.id ?? 0, topEvent?.id ?? 0)
    }

    func testTopAndBottomSelectionCommandsPublishEdgeScrollAnchors() {
        let model = makeModel(entries: entries(["a.txt", "b.txt", "c.txt"]))

        model.handle(.bottom)
        XCTAssertEqual(model.selectedEntry?.name, "c.txt")
        XCTAssertEqual(model.selectionScrollEvent?.anchor, .bottom)

        model.handle(.top)
        XCTAssertEqual(model.selectedEntry?.name, "a.txt")
        XCTAssertEqual(model.selectionScrollEvent?.anchor, .top)
    }

    func testFirstCharacterCyclingMovesBetweenMatchingRows() {
        let model = makeModel(entries: entries(["alpha.txt", "beta.txt", "build.log", "gamma.txt"]))

        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "beta.txt")
        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "build.log")
    }

    func testFirstCharacterCyclingIgnoresCaseAndLeadingSymbols() {
        let sampleTarget = TestFixtures.sampleCloudTargetName
        let model = makeModel(entries: entries([
            "alpha.txt",
            "_\(sampleTarget)",
            sampleTarget,
            sampleTarget.lowercased()
        ]))

        model.handle(.alphaNumeric("s"))
        XCTAssertEqual(model.selectedEntry?.name, "_\(sampleTarget)")

        model.handle(.alphaNumeric("s"))
        XCTAssertEqual(model.selectedEntry?.name, sampleTarget)

        model.handle(.alphaNumeric("s"))
        XCTAssertEqual(model.selectedEntry?.name, sampleTarget.lowercased())

        model.handle(.alphaNumeric("s"))
        XCTAssertEqual(model.selectedEntry?.name, "_\(sampleTarget)")
    }

    func testShiftFirstCharacterCyclingMovesToPreviousMatch() {
        let sampleTarget = TestFixtures.sampleCloudTargetName
        let model = makeModel(entries: entries([
            "alpha.txt",
            "_\(sampleTarget)",
            sampleTarget,
            sampleTarget.lowercased()
        ]))

        model.handle(.bottom)
        XCTAssertEqual(model.selectedEntry?.name, sampleTarget.lowercased())

        model.handle(.shiftAlphaNumeric("s"))
        XCTAssertEqual(model.selectedEntry?.name, sampleTarget)

        model.handle(.shiftAlphaNumeric("s"))
        XCTAssertEqual(model.selectedEntry?.name, "_\(sampleTarget)")

        model.handle(.shiftAlphaNumeric("s"))
        XCTAssertEqual(model.selectedEntry?.name, sampleTarget.lowercased())
    }

    func testAlphaNumericInputIsIgnoredWhileRenaming() {
        let model = makeModel(entries: entries(["alpha.txt", "beta.txt", "gamma.txt"]))

        perform(.rename, on: model)
        model.handle(.alphaNumeric("g"))

        XCTAssertEqual(model.focusState, .renaming)
        XCTAssertEqual(model.selectedEntry?.name, "alpha.txt")
        XCTAssertEqual(model.renameState?.proposedName, "alpha.txt")
    }

    func testSpaceTogglesSelectionAndShiftSpaceSelectsRange() {
        let model = makeModel(entries: entries(["one.txt", "two.txt", "three.txt", "four.txt"]))

        model.handle(.space)
        model.handle(.down)
        model.handle(.down)
        model.handle(.shiftSpace)

        XCTAssertEqual(model.selectedURLs.map(\.lastPathComponent), ["one.txt", "two.txt", "three.txt"])
    }

    func testPreparedSpaceTapTogglesRowFocusedWhenSpaceStarted() {
        let model = makeModel(entries: entries(["one.txt", "two.txt", "three.txt"]))

        model.handle(.down)
        model.handle(.prepareSpaceInteraction)
        model.handle(.down)
        model.handle(.space)

        XCTAssertEqual(model.selectedURLs.map(\.lastPathComponent), ["two.txt"])
        XCTAssertEqual(model.selectedEntry?.name, "three.txt")
    }

    func testRightOnFileSetsPaneWobble() {
        let model = makeModel(entries: entries(["file.txt"]))

        model.handle(.right)

        XCTAssertEqual(model.wobbleReason, .cannotEnterFile)
    }

    func testRightEntersSymbolicLinkThatResolvesToDirectory() {
        let home = TestFixtures.userHome
        let link = TestFixtures.sampleCloudTargetLink(in: home)
        let linkedDirectory = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .appendingPathComponent(TestFixtures.sampleCloudTargetName, isDirectory: true)
        let child = linkedDirectory.appendingPathComponent("Reports", isDirectory: true)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            home: [symbolicLinkEntry(link)],
            linkedDirectory: [directoryEntry(child)]
        ], resolvedDirectoriesByURL: [link: linkedDirectory])
        let model = FileBrowserModel(
            fileSystem: client,
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, linkedDirectory.standardizedFileURL)
        XCTAssertEqual(model.entries.map(\.name), ["Reports"])
        XCTAssertNil(model.wobbleReason)
    }

    func testRightOnPackageDoesNotEnterEvenWhenPackageIsFilesystemDirectory() {
        let home = URL(fileURLWithPath: "/Users/test")
        let appBundle = home.appendingPathComponent("Bucky.app", isDirectory: true)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            home: [packageEntry(appBundle)],
            appBundle: [fileEntry(appBundle.appendingPathComponent("Contents"))]
        ])
        let model = FileBrowserModel(
            fileSystem: client,
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, home)
        XCTAssertEqual(model.wobbleReason, .cannotEnterFile)
    }

    func testRepeatedInvalidRightPublishesDistinctWobbleEvents() {
        let model = makeModel(entries: entries(["file.txt"]))
        var events: [FileBrowserWobbleEvent] = []
        let cancellable = model.$wobbleEvent
            .compactMap { $0 }
            .sink { events.append($0) }

        model.handle(.right)
        model.handle(.right)

        XCTAssertEqual(events.map(\.reason), [.cannotEnterFile, .cannotEnterFile])
        XCTAssertNotEqual(events[0].id, events[1].id)
        cancellable.cancel()
    }

    func testShiftSpaceAfterDirectoryChangePreservesSelectionsFromOtherDirectories() {
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
        XCTAssertEqual(model.selectedURLs.map(\.lastPathComponent), ["gamma.txt", "only.txt"])
    }

    func testStaleSelectionPrunesCurrentDirectoryItemsOnly() {
        let home = URL(fileURLWithPath: "/Users/test")
        let other = URL(fileURLWithPath: "/Users/other")
        let model = makeModel(entries: entries(["one.txt", "two.txt"], in: home), home: home)
        let otherSelection = other.appendingPathComponent("kept.txt")

        model.handle(.space)
        model.addSelectedURLForTesting(otherSelection)
        model.replaceEntriesForTesting(entries(["two.txt"], in: home))

        XCTAssertEqual(model.selectedURLs, [otherSelection])
    }

    func testActionAvailabilityChangesForSingleAndMultipleSelections() {
        let model = makeModel(entries: entries(["one.txt", "two.txt"]))

        model.handle(.space)
        XCTAssertEqual(model.availableActions, [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash])
        XCTAssertEqual(model.focusableActions, [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash])

        model.handle(.down)
        model.handle(.shiftSpace)
        XCTAssertEqual(model.availableActions, [.batchRename, .copyPaths, .copy, .move, .moveToTrash])
        XCTAssertEqual(model.focusableActions, [.batchRename, .copyPaths, .copy, .move, .moveToTrash])
    }

    func testUnmountableMountShowsUnmountActionOnlyForSingleFocusedVolume() {
        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let mount = volumes.appendingPathComponent("Backup", isDirectory: true)
        let model = makeModel(entries: [mountEntry(mount, canUnmount: true)], home: volumes)

        XCTAssertEqual(model.availableActions, [.open, .revealInFinder, .copyPath, .unmount])

        model.handle(.space)

        XCTAssertEqual(model.availableActions, [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash])
    }

    func testUnmountActionRequiresConfirmationBeforeCallingNativeService() {
        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let mount = volumes.appendingPathComponent("Backup", isDirectory: true)
        let service = RecordingFileBrowserServices()
        let model = makeModel(entries: [mountEntry(mount, canUnmount: true)], home: volumes, fileServices: service)

        perform(.unmount, on: model)

        XCTAssertEqual(model.focusState, .confirming(.unmount(mount)))
        XCTAssertEqual(service.events, [])

        model.handle(.open)

        XCTAssertEqual(service.events, [.unmount(mount)])
        XCTAssertEqual(model.focusState, .browse)
    }

    func testSidebarIncludesMountsShortcutAfterUserPins() {
        let home = URL(fileURLWithPath: "/Users/test")
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [home: [], projects: []])

        model.togglePin(projects)

        XCTAssertEqual(model.sidebarDirectories.map(\.path), [projects.path, "/Volumes"])
    }

    func testActionOverlayKeyboardSelectionAndReturnStartsFocusedAction() {
        let model = makeModel(entries: entries(["one.txt"]))

        model.handle(.space)
        model.handle(.open)
        model.handle(.down)
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
        model.handle(.down)

        XCTAssertEqual(model.focusableActions[model.focusedActionIndex], .copy)

        model.handle(.open)

        XCTAssertEqual(model.focusState, .transferPending(.copy(model.selectedURLs)))
    }

    func testEverySingleSelectionFocusedActionProducesStateOrIntent() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        let expected: [(FileBrowserAction, FileBrowserFocusState, [RecordingFileBrowserServices.Event])] = [
            (.open, .browse, [.open(selectedURL)]),
            (.rename, .renaming, []),
            (.revealInFinder, .browse, [.revealInFinder([selectedURL])]),
            (.copyPath, .browse, [.copyPaths([selectedURL])]),
            (.copy, .transferPending(.copy([selectedURL])), []),
            (.move, .transferPending(.move([selectedURL])), []),
            (.moveToTrash, .confirming(.trash([selectedURL], step: 1)), [])
        ]

        for (action, expectedFocusState, expectedEvents) in expected {
            service.reset()
            let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

            perform(action, on: model)

            XCTAssertEqual(model.focusState, expectedFocusState, "Unexpected focus state for \(action)")
            XCTAssertEqual(service.events, expectedEvents, "Unexpected service calls for \(action)")
        }
    }

    func testEveryMultipleSelectionFocusedActionProducesStateOrIntent() {
        let home = URL(fileURLWithPath: "/Users/test")
        let urls = [
            home.appendingPathComponent("one.txt"),
            home.appendingPathComponent("two.txt")
        ]
        let service = RecordingFileBrowserServices()
        let expected: [(FileBrowserAction, FileBrowserFocusState, [RecordingFileBrowserServices.Event])] = [
            (.batchRename, .renaming, []),
            (.copyPaths, .browse, [.copyPaths(urls)]),
            (.copy, .transferPending(.copy(urls)), []),
            (.move, .transferPending(.move(urls)), []),
            (.moveToTrash, .confirming(.trash(urls, step: 1)), [])
        ]

        for (action, expectedFocusState, expectedEvents) in expected {
            service.reset()
            let model = makeModel(entries: entries(["one.txt", "two.txt"], in: home), home: home, fileServices: service)
            model.handle(.space)
            model.handle(.down)
            model.handle(.shiftSpace)

            perform(action, on: model)

            XCTAssertEqual(model.focusState, expectedFocusState, "Unexpected focus state for \(action)")
            XCTAssertEqual(service.events, expectedEvents, "Unexpected service calls for \(action)")
        }
    }

    func testFocusedOpenRevealAndCopyPathsExecuteThroughNativeService() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

        perform(.open, on: model)
        perform(.revealInFinder, on: model)
        perform(.copyPath, on: model)

        XCTAssertEqual(service.events, [
            .open(selectedURL),
            .revealInFinder([selectedURL]),
            .copyPaths([selectedURL])
        ])
        XCTAssertEqual(model.focusState, .browse)
    }

    func testRenameConfirmCallsNativeServiceAndEscapeReturnsToActions() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

        perform(.rename, on: model)
        XCTAssertEqual(model.renameState?.proposedName, "one.txt")

        model.setRenameText("renamed.txt")
        model.handle(.open)

        XCTAssertEqual(service.events, [.rename(selectedURL, "renamed.txt")])
        XCTAssertEqual(model.focusState, .browse)

        perform(.rename, on: model)
        model.handle(.close)

        XCTAssertEqual(model.focusState, .previewActions)
        XCTAssertNil(model.renameState)
    }

    func testBatchRenameConfirmCallsNativeServiceWithBaseName() {
        let home = URL(fileURLWithPath: "/Users/test")
        let urls = [
            home.appendingPathComponent("one.txt"),
            home.appendingPathComponent("two.txt")
        ]
        let service = RecordingFileBrowserServices()
        let model = makeModel(entries: entries(["one.txt", "two.txt"], in: home), home: home, fileServices: service)

        model.handle(.space)
        model.handle(.down)
        model.handle(.shiftSpace)
        perform(.batchRename, on: model)
        XCTAssertEqual(model.renameState?.proposedName, "Untitled")

        model.setRenameText("Screenshot")
        model.handle(.open)

        XCTAssertEqual(service.events, [.batchRename(urls, "Screenshot")])
        XCTAssertEqual(model.focusState, .browse)
    }

    func testTransferConfirmationExecutesCopyAndMoveThroughNativeService() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

        model.handle(.space)
        model.startTransfer(.copy)
        model.handle(.open)
        model.handle(.open)

        XCTAssertEqual(service.events, [.copy([selectedURL], home, .keepBoth)])
        XCTAssertEqual(model.focusState, .browse)

        model.startTransfer(.move)
        model.handle(.open)
        model.handle(.open)

        XCTAssertEqual(service.events, [
            .copy([selectedURL], home, .keepBoth),
            .move([selectedURL], home, .keepBoth)
        ])
    }

    func testTrashRequiresDoubleConfirmationBeforeNativeTrash() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

        model.handle(.space)
        model.requestTrashConfirmation()
        model.handle(.open)

        XCTAssertEqual(service.events, [])
        XCTAssertEqual(model.focusState, .confirming(.trash([selectedURL], step: 2)))

        model.handle(.open)

        XCTAssertEqual(service.events, [.trash([selectedURL])])
        XCTAssertEqual(model.focusState, .browse)
        XCTAssertEqual(model.selectedURLs, [])
    }

    func testEscapeBehaviorForQuickLookRenameTransferConfirmationAndConflict() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        service.conflicts = [FileBrowserConflict(
            source: selectedURL,
            destination: home.appendingPathComponent("one.txt")
        )]
        let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

        model.handle(.space)
        model.handle(.beginSpaceHold)
        model.handle(.close)
        XCTAssertEqual(model.focusState, .browse)
        XCTAssertEqual(model.selectedURLs, [selectedURL])

        perform(.rename, on: model)
        model.handle(.close)
        XCTAssertEqual(model.focusState, .previewActions)

        model.startTransfer(.copy)
        model.handle(.close)
        XCTAssertEqual(model.focusState, .previewActions)

        model.startTransfer(.copy)
        model.handle(.open)
        model.handle(.close)
        XCTAssertEqual(model.focusState, .previewActions)

        model.startTransfer(.copy)
        model.handle(.open)
        model.handle(.open)
        XCTAssertEqual(model.focusState, .confirming(.conflict(.copy([selectedURL]), destination: home, conflicts: service.conflicts)))
        model.handle(.close)
        XCTAssertEqual(model.focusState, .previewActions)
    }

    func testQuickLookPreviewModeComesFromNativeServiceAndReleaseDismisses() {
        let nativeService = RecordingFileBrowserServices()
        nativeService.previewMode = .nativeThumbnail
        let nativeModel = makeModel(entries: entries(["image.png"]), fileServices: nativeService)

        nativeModel.handle(.beginSpaceHold)

        XCTAssertEqual(nativeModel.focusState, .quickLook(FileBrowserPreview(
            url: nativeModel.selectedEntry!.url,
            mode: .nativeThumbnail
        )))

        nativeModel.handle(.endSpaceHold)
        XCTAssertEqual(nativeModel.focusState, .browse)

        let fallbackService = RecordingFileBrowserServices()
        fallbackService.previewMode = .metadataFallback
        let fallbackModel = makeModel(entries: entries(["archive.bin"]), fileServices: fallbackService)

        fallbackModel.handle(.beginSpaceHold)

        XCTAssertEqual(fallbackModel.focusState, .quickLook(FileBrowserPreview(
            url: fallbackModel.selectedEntry!.url,
            mode: .metadataFallback
        )))
    }

    func testQuickLookPreviewFollowsSelectionWhileHeld() {
        let service = RecordingFileBrowserServices()
        let model = makeModel(entries: entries(["one.png", "two.mov", "three.swift"]), fileServices: service)
        let firstURL = model.entries[0].url
        let secondURL = model.entries[1].url
        let thirdURL = model.entries[2].url
        service.previewModesByURL = [
            firstURL: .nativeThumbnail,
            secondURL: .video,
            thirdURL: .codeText
        ]

        model.handle(.beginSpaceHold)
        XCTAssertEqual(model.focusState, .quickLook(FileBrowserPreview(url: firstURL, mode: .nativeThumbnail)))

        model.handle(.down)
        XCTAssertEqual(model.focusState, .quickLook(FileBrowserPreview(url: secondURL, mode: .video)))

        model.handle(.down)
        XCTAssertEqual(model.focusState, .quickLook(FileBrowserPreview(url: thirdURL, mode: .codeText)))
    }

    func testQuickLookThumbnailLoadingUsesNativeServiceForSuccessAndFailure() {
        let service = RecordingFileBrowserServices()
        let thumbnail = NSImage(size: NSSize(width: 12, height: 12))
        service.thumbnailResult = thumbnail
        let model = makeModel(entries: entries(["image.png"]), fileServices: service)
        let url = model.selectedEntry!.url
        var successImage: NSImage?

        model.loadPreviewThumbnail(for: url, size: CGSize(width: 64, height: 32), scale: 2) { image in
            successImage = image
        }

        XCTAssertIdentical(successImage, thumbnail)
        XCTAssertEqual(service.thumbnailRequests, [
            RecordingFileBrowserServices.ThumbnailRequest(
                url: url,
                size: CGSize(width: 64, height: 32),
                scale: 2
            )
        ])

        service.thumbnailResult = nil
        var failureImage: NSImage? = thumbnail
        model.loadPreviewThumbnail(for: url, size: CGSize(width: 128, height: 64), scale: 1) { image in
            failureImage = image
        }

        XCTAssertNil(failureImage)
        XCTAssertEqual(service.thumbnailRequests.last, RecordingFileBrowserServices.ThumbnailRequest(
            url: url,
            size: CGSize(width: 128, height: 64),
            scale: 1
        ))
    }

    func testIconLoadingUsesNativeService() {
        let service = RecordingFileBrowserServices()
        let icon = NSImage(size: NSSize(width: 10, height: 10))
        service.iconResult = icon
        let model = makeModel(entries: entries(["notes.txt"]), fileServices: service)
        let url = model.selectedEntry!.url

        let loadedIcon = model.icon(for: url)

        XCTAssertIdentical(loadedIcon, icon)
        XCTAssertEqual(service.iconRequests, [url])
    }

    func testConflictRowsDefaultToKeepBothAndExecuteFocusedOption() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        service.conflicts = [FileBrowserConflict(
            source: selectedURL,
            destination: home.appendingPathComponent("one.txt")
        )]
        let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

        model.handle(.space)
        model.startTransfer(.copy)
        model.handle(.open)
        model.handle(.open)

        XCTAssertEqual(model.focusedConflictResolution, .keepBoth)
        XCTAssertEqual(model.focusState, .confirming(.conflict(.copy([selectedURL]), destination: home, conflicts: service.conflicts)))

        model.handle(.down)
        XCTAssertEqual(model.focusedConflictResolution, .replace)
        model.handle(.open)

        XCTAssertEqual(service.events, [.copy([selectedURL], home, .replace)])
        XCTAssertEqual(model.focusState, .browse)
    }

    func testConflictCancelOptionDoesNotExecuteTransfer() {
        let home = URL(fileURLWithPath: "/Users/test")
        let selectedURL = home.appendingPathComponent("one.txt")
        let service = RecordingFileBrowserServices()
        service.conflicts = [FileBrowserConflict(
            source: selectedURL,
            destination: home.appendingPathComponent("one.txt")
        )]
        let model = makeModel(entries: entries(["one.txt"], in: home), home: home, fileServices: service)

        model.handle(.space)
        model.startTransfer(.move)
        model.handle(.open)
        model.handle(.open)
        model.handle(.down)
        model.handle(.down)
        model.handle(.open)

        XCTAssertEqual(model.focusedConflictResolution, .cancel)
        XCTAssertEqual(service.events, [])
        XCTAssertEqual(model.focusState, .browse)
    }

    func testOperationFailureShowsStatusAndKeepsRecoverableFocus() {
        let service = RecordingFileBrowserServices()
        service.error = TestFileBrowserServiceError.failed
        let model = makeModel(entries: entries(["one.txt"]), fileServices: service)

        perform(.open, on: model)

        XCTAssertEqual(model.focusState, .previewActions)
        XCTAssertEqual(model.statusMessage, "failed")
    }

    func testOpenPinnedDirectoryNavigatesThroughModel() {
        let home = URL(fileURLWithPath: "/Users/test")
        let pinned = home.appendingPathComponent("Projects", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [
            home: [],
            pinned: entries(["README.md"], in: pinned)
        ])

        model.openPinnedDirectory(pinned)

        XCTAssertEqual(model.currentDirectory, pinned)
        XCTAssertEqual(model.entries.map(\.name), ["README.md"])
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
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )
        let pin = URL(fileURLWithPath: "/Users/test/Projects")

        model.togglePin(pin)

        XCTAssertEqual(model.pinnedDirectories, [pin])
        XCTAssertEqual(store.state.pinnedDirectories, [pin])

        model.togglePin(pin)

        XCTAssertEqual(model.pinnedDirectories, [])
        XCTAssertEqual(store.state.pinnedDirectories, [])
    }

    func testCommandPinTogglesSelectedFileOrDirectory() {
        let home = URL(fileURLWithPath: "/Users/test")
        let model = makeModel(entries: entries(["notes.txt", "Projects/"], in: home), home: home)

        model.handle(.togglePin)
        XCTAssertEqual(model.pinnedDirectories.map(\.lastPathComponent), ["notes.txt"])

        model.handle(.down)
        model.handle(.togglePin)
        XCTAssertEqual(model.pinnedDirectories.map(\.lastPathComponent), ["notes.txt", "Projects"])

        model.handle(.togglePin)
        XCTAssertEqual(model.pinnedDirectories.map(\.lastPathComponent), ["notes.txt"])
    }

    func testOptionFocusNavigatesPinnedItemsAndReleaseReturnsToBrowseWithoutOpening() {
        let home = URL(fileURLWithPath: "/Users/test")
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let archive = home.appendingPathComponent("_Archive", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [
            home: [directoryEntry(projects), directoryEntry(archive)],
            projects: [],
            archive: []
        ])

        model.togglePin(projects)
        model.togglePin(archive)

        model.handle(.beginPinnedFocus)
        XCTAssertEqual(model.focusState, .pinnedItems)
        XCTAssertEqual(model.focusedPinnedURL, projects)

        model.handle(.alphaNumeric("a"))
        XCTAssertEqual(model.focusedPinnedURL, archive)

        model.handle(.endPinnedFocus)
        XCTAssertEqual(model.focusState, .browse)
        XCTAssertEqual(model.currentDirectory, home)
    }

    func testReturnWhilePinnedFocusOpensFocusedPinnedDirectory() {
        let home = URL(fileURLWithPath: "/Users/test")
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let archive = home.appendingPathComponent("Archive", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [
            home: [],
            projects: entries(["README.md"], in: projects),
            archive: entries(["notes.txt"], in: archive)
        ])

        model.togglePin(projects)
        model.togglePin(archive)
        model.handle(.beginPinnedFocus)
        model.handle(.down)
        model.handle(.open)

        XCTAssertEqual(model.currentDirectory, archive)
        XCTAssertEqual(model.entries.map(\.name), ["notes.txt"])
        XCTAssertEqual(model.focusState, .browse)
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
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.handle(.right)
        model.handle(.left)
        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, child)
    }

    func testLeftSelectsPreviousChildSoRightRestoresWhenChildIsNotFirstRow() {
        let home = URL(fileURLWithPath: "/Users/test")
        let archive = home.appendingPathComponent("Archive", isDirectory: true)
        let child = home.appendingPathComponent("Projects", isDirectory: true)
        let client = StubFileSystemClient(
            home: home,
            entriesByDirectory: [
                home: [directoryEntry(archive), directoryEntry(child)],
                child: []
            ]
        )
        let store = InMemoryFileBrowserStore(state: .defaultValue)
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.handle(.alphaNumeric("p"))
        model.handle(.right)
        model.handle(.left)

        XCTAssertEqual(model.currentDirectory, home)
        XCTAssertEqual(model.selectedEntry?.url, child)

        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, child)
    }

    func testRightDirectoryNavigationPublishesDeeperTransition() {
        let home = URL(fileURLWithPath: "/Users/test")
        let child = home.appendingPathComponent("Projects", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [
            home: [directoryEntry(child)],
            child: []
        ])

        XCTAssertNil(model.navigationTransition)

        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, child)
        XCTAssertEqual(model.navigationTransition?.direction, .deeper)
        XCTAssertEqual(model.navigationTransition?.id, 1)
    }

    func testLeftDirectoryNavigationPublishesParentTransitionAndSelectsTraversedChild() {
        let home = URL(fileURLWithPath: "/Users/test")
        let archive = home.appendingPathComponent("Archive", isDirectory: true)
        let child = home.appendingPathComponent("Projects", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [
            home: [directoryEntry(archive), directoryEntry(child)],
            child: []
        ])

        model.handle(.alphaNumeric("p"))
        model.handle(.right)
        let childDirectoryEvent = model.selectionScrollEvent
        model.handle(.left)

        XCTAssertEqual(model.currentDirectory, home)
        XCTAssertEqual(model.selectedEntry?.url, child)
        XCTAssertEqual(model.navigationTransition?.direction, .parent)
        XCTAssertEqual(model.navigationTransition?.id, 2)
        XCTAssertEqual(model.selectionScrollEvent?.url, child)
        XCTAssertEqual(model.selectionScrollEvent?.anchor, .top)
        XCTAssertGreaterThan(model.selectionScrollEvent?.id ?? 0, childDirectoryEvent?.id ?? 0)
    }

    func testRapidLeftThenRightFollowsRememberedChainWhenChildrenAreNotFirstRows() {
        let home = URL(fileURLWithPath: "/Users/test")
        let archive = home.appendingPathComponent("Archive", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let docs = projects.appendingPathComponent("Docs", isDirectory: true)
        let notes = projects.appendingPathComponent("Notes", isDirectory: true)
        let client = StubFileSystemClient(
            home: home,
            entriesByDirectory: [
                home: [directoryEntry(archive), directoryEntry(projects)],
                projects: [directoryEntry(docs), directoryEntry(notes)],
                notes: []
            ]
        )
        let store = InMemoryFileBrowserStore(state: .defaultValue)
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.handle(.alphaNumeric("p"))
        model.handle(.right)
        model.handle(.alphaNumeric("n"))
        model.handle(.right)
        model.handle(.left)
        model.handle(.left)
        model.handle(.right)
        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, notes)
    }

    func testRightAfterLeftRestoresSelectionInsideRememberedDirectory() {
        let home = URL(fileURLWithPath: "/Users/test")
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let alpha = projects.appendingPathComponent("alpha.txt")
        let beta = projects.appendingPathComponent("beta.txt")
        let model = makeModel(home: home, entriesByDirectory: [
            home: [directoryEntry(projects)],
            projects: [
                fileEntry(alpha),
                fileEntry(beta)
            ]
        ])

        model.handle(.right)
        model.handle(.down)
        XCTAssertEqual(model.selectedEntry?.url, beta)

        model.handle(.left)
        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, projects)
        XCTAssertEqual(model.selectedEntry?.url, beta)
    }

    func testTraversalChainRestoresDeepestSelectedEntryAcrossNewModel() {
        let home = URL(fileURLWithPath: "/Users/test")
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let docs = projects.appendingPathComponent("Docs", isDirectory: true)
        let beta = docs.appendingPathComponent("beta.txt")
        let entriesByDirectory: [URL: [FileBrowserEntry]] = [
            home: [directoryEntry(projects)],
            projects: [directoryEntry(docs)],
            docs: [
                fileEntry(docs.appendingPathComponent("alpha.txt")),
                fileEntry(beta)
            ]
        ]
        let client = StubFileSystemClient(home: home, entriesByDirectory: entriesByDirectory)
        let store = InMemoryFileBrowserStore(state: .defaultValue)
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.handle(.right)
        model.handle(.right)
        model.handle(.down)
        model.handle(.left)
        model.handle(.left)

        let restoredModel = FileBrowserModel(
            fileSystem: client,
            store: InMemoryFileBrowserStore(state: store.state),
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        restoredModel.handle(.right)
        restoredModel.handle(.right)

        XCTAssertEqual(restoredModel.currentDirectory, docs)
        XCTAssertEqual(restoredModel.selectedEntry?.url, beta)
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
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.handle(.right)
        model.handle(.left)
        model.handle(.down)
        model.handle(.right)

        XCTAssertEqual(model.currentDirectory, other)
    }

    func testDirectoryHistoryBackAndForwardCrossesUnrelatedPinnedDirectories() {
        let home = URL(fileURLWithPath: "/Users/test")
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let archive = URL(fileURLWithPath: "/Volumes/External/Archive", isDirectory: true)
        let model = makeModel(home: home, entriesByDirectory: [
            home: [],
            projects: entries(["project.txt"], in: projects),
            archive: entries(["archive.txt"], in: archive)
        ])

        model.openPinnedDirectory(projects)
        model.openPinnedDirectory(archive)
        XCTAssertEqual(model.currentDirectory, archive)

        model.handle(.historyBack)
        XCTAssertEqual(model.currentDirectory, projects)

        model.handle(.historyBack)
        XCTAssertEqual(model.currentDirectory, home)

        model.handle(.historyForward)
        XCTAssertEqual(model.currentDirectory, projects)

        model.handle(.historyForward)
        XCTAssertEqual(model.currentDirectory, archive)
    }

    func testSetSortReloadsEntriesAndPersistsSelection() {
        let home = URL(fileURLWithPath: "/Users/test")
        let client = RecordingFileSystemClient(home: home, entriesByDirectory: [
            home: entries(["small.txt", "large.txt"], in: home)
        ])
        let store = InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: home,
            sort: .name,
            traversalChain: []
        ))
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.setSort(.size)

        XCTAssertEqual(model.sort, .size)
        XCTAssertEqual(store.state.sort, .size)
        XCTAssertEqual(client.entryRequests.filter { $0.directory == home }.map(\.sort), [.name, .size])
        XCTAssertEqual(client.entryRequests.filter { $0.directory == home }.map(\.foldersFirst), [false, false])
    }

    func testToggleFoldersFirstReloadsEntriesAndPersistsSelection() {
        let home = URL(fileURLWithPath: "/Users/test")
        let client = RecordingFileSystemClient(home: home, entriesByDirectory: [
            home: entries(["Folder/", "file.txt"], in: home)
        ])
        let store = InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: home,
            sort: .dateCreated,
            foldersFirst: false,
            traversalChain: []
        ))
        let model = FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client)
        )

        model.setFoldersFirst(true)

        XCTAssertTrue(model.foldersFirst)
        XCTAssertTrue(store.state.foldersFirst)
        XCTAssertEqual(model.sort, .dateCreated)
        XCTAssertEqual(client.entryRequests.filter { $0.directory == home }.map(\.sort), [.dateCreated, .dateCreated])
        XCTAssertEqual(client.entryRequests.filter { $0.directory == home }.map(\.foldersFirst), [false, true])
    }

    func testSortReloadKeepsLastLookedFileWhenEntryOrderChanges() {
        let home = URL(fileURLWithPath: "/Users/test")
        let stream = ManualDirectoryStream()
        let model = FileBrowserModel(
            fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: stream
        )

        let alpha = home.appendingPathComponent("alpha.txt")
        let beta = home.appendingPathComponent("beta.txt")
        stream.completeRequest(at: 0, with: .success([fileEntry(alpha), fileEntry(beta)]))

        model.handle(.down)
        XCTAssertEqual(model.selectedEntry?.url, beta)

        model.setSort(.size)
        stream.completeRequest(at: 1, with: .success([fileEntry(beta), fileEntry(alpha)]))

        XCTAssertEqual(model.selectedEntry?.url, beta)
    }

    func testCurrentDirectoryObservationReloadsOpenDirectoryAndKeepsSelection() {
        let home = URL(fileURLWithPath: "/Users/test")
        let observer = ManualDirectoryObserver()
        let stream = ManualDirectoryStream()
        let model = FileBrowserModel(
            fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: stream,
            directoryObserver: observer
        )

        let alpha = home.appendingPathComponent("alpha.txt")
        let beta = home.appendingPathComponent("beta.txt")
        let gamma = home.appendingPathComponent("gamma.txt")
        stream.completeRequest(at: 0, with: .success([fileEntry(alpha), fileEntry(beta)]))
        model.handle(.down)
        XCTAssertEqual(model.selectedEntry?.url, beta)
        XCTAssertEqual(observer.observedDirectories, [home.standardizedFileURL])

        observer.triggerLatestChange()
        XCTAssertEqual(stream.requests.count, 2)
        stream.completeRequest(at: 1, with: .success([fileEntry(alpha), fileEntry(beta), fileEntry(gamma)]))

        XCTAssertEqual(model.entries.map(\.url), [alpha, beta, gamma])
        XCTAssertEqual(model.selectedEntry?.url, beta)
    }

    func testDirectorySnapshotsTrackCurrentVisibleDirectoryOnly() {
        let home = URL(fileURLWithPath: "/Users/test")
        let child = home.appendingPathComponent("Projects", isDirectory: true)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            home: [directoryEntry(child), fileEntry(home.appendingPathComponent("notes.txt"))],
            child: [fileEntry(child.appendingPathComponent("README.md"))]
        ])
        let model = FileBrowserModel(fileSystem: client, store: InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: home,
            sort: .name,
            traversalChain: []
        )), directoryStream: ImmediateDirectoryStream(fileSystem: client))

        XCTAssertEqual(model.directorySnapshots.map(\.directory), [home])
        XCTAssertEqual(model.directorySnapshots[0].entries.map(\.name), ["Projects", "notes.txt"])
    }

    func testEntryLookupFindsMetadataFromDirectorySnapshots() {
        let home = URL(fileURLWithPath: "/Users/test")
        let readme = home.appendingPathComponent("README.md")
        let modifiedAt = Date(timeIntervalSince1970: 1_234)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            home: [FileBrowserEntry(
                url: readme,
                kind: .file,
                size: 42,
                createdAt: nil,
                modifiedAt: modifiedAt,
                isHidden: false
            )]
        ])
        let model = FileBrowserModel(fileSystem: client, store: InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: home,
            sort: .name,
            traversalChain: []
        )), directoryStream: ImmediateDirectoryStream(fileSystem: client))

        XCTAssertEqual(model.entry(for: readme)?.modifiedAt, modifiedAt)
        XCTAssertEqual(model.entry(for: readme)?.size, 42)
    }

    func testArrowNavigationDoesNotRereadUnchangedCurrentSnapshot() {
        let home = URL(fileURLWithPath: "/Users/test")
        let client = RecordingFileSystemClient(home: home, entriesByDirectory: [
            home: entries(["alpha.txt", "beta.txt", "gamma.txt"], in: home)
        ])
        let model = FileBrowserModel(fileSystem: client, store: InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: home,
            sort: .name,
            traversalChain: []
        )), directoryStream: ImmediateDirectoryStream(fileSystem: client))
        let baseline = client.entryRequests

        model.handle(.down)
        model.handle(.down)
        model.handle(.up)

        XCTAssertEqual(model.selectedEntry?.name, "beta.txt")
        XCTAssertEqual(client.entryRequests.map(requestDescription), baseline.map(requestDescription))
    }

    func testAlphaSelectionKeepsSnapshotsOnCurrentDirectoryOnly() {
        let home = URL(fileURLWithPath: "/Users/test")
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let archive = home.appendingPathComponent("Archive", isDirectory: true)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            home: [directoryEntry(projects), directoryEntry(archive)],
            projects: [fileEntry(projects.appendingPathComponent("project.txt"))],
            archive: [fileEntry(archive.appendingPathComponent("archive.txt"))]
        ])
        let model = FileBrowserModel(fileSystem: client, store: InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: home,
            sort: .name,
            traversalChain: []
        )), directoryStream: ImmediateDirectoryStream(fileSystem: client))

        model.handle(.alphaNumeric("a"))

        XCTAssertEqual(model.selectedEntry?.url, archive)
        XCTAssertEqual(model.directorySnapshots.map(\.directory), [home])
        XCTAssertEqual(model.directorySnapshots.last?.entries.map(\.name), ["Projects", "Archive"])
    }

    private func makeModel(
        entries: [FileBrowserEntry] = [],
        persisted: FileBrowserPersistedState = .defaultValue,
        home: URL = TestFixtures.userHome,
        fileServices: FileBrowserNativeServicing = RecordingFileBrowserServices()
    ) -> FileBrowserModel {
        let client = StubFileSystemClient(home: home, entriesByDirectory: [home: entries])
        let store = InMemoryFileBrowserStore(state: persisted)
        return FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client),
            fileServices: fileServices
        )
    }

    private func makeModel(
        persisted: FileBrowserPersistedState = .defaultValue,
        home: URL = TestFixtures.userHome,
        entriesByDirectory: [URL: [FileBrowserEntry]],
        fileServices: FileBrowserNativeServicing = RecordingFileBrowserServices()
    ) -> FileBrowserModel {
        let client = StubFileSystemClient(home: home, entriesByDirectory: entriesByDirectory)
        let store = InMemoryFileBrowserStore(state: persisted)
        return FileBrowserModel(
            fileSystem: client,
            store: store,
            directoryStream: ImmediateDirectoryStream(fileSystem: client),
            fileServices: fileServices
        )
    }

    private func entries(_ names: [String]) -> [FileBrowserEntry] {
        entries(names, in: TestFixtures.userHome)
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

    private func symbolicLinkEntry(_ url: URL) -> FileBrowserEntry {
        FileBrowserEntry(url: url, kind: .symbolicLink, size: nil, createdAt: nil, modifiedAt: nil, isHidden: false)
    }

    private func packageEntry(_ url: URL) -> FileBrowserEntry {
        FileBrowserEntry(url: url, kind: .package, size: nil, createdAt: nil, modifiedAt: nil, isHidden: false)
    }

    private func fileEntry(_ url: URL) -> FileBrowserEntry {
        FileBrowserEntry(url: url, kind: .file, size: 1, createdAt: nil, modifiedAt: nil, isHidden: false)
    }

    private func mountEntry(_ url: URL, canUnmount: Bool) -> FileBrowserEntry {
        FileBrowserEntry(
            url: url,
            kind: .directory,
            size: nil,
            createdAt: nil,
            modifiedAt: nil,
            isHidden: false,
            isMount: true,
            canUnmount: canUnmount
        )
    }

    private func perform(_ action: FileBrowserAction, on model: FileBrowserModel) {
        model.handle(.open)
        guard let index = model.focusableActions.firstIndex(of: action) else {
            XCTFail("Missing focusable action \(action)")
            return
        }
        for _ in 0..<index {
            model.handle(.down)
        }
        model.handle(.open)
    }

    private func requestDescription(_ request: (directory: URL, sort: FileBrowserSort, foldersFirst: Bool)) -> String {
        "\(request.directory.path)|\(request.sort.rawValue)|\(request.foldersFirst)"
    }
}
