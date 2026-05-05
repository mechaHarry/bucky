import XCTest
import AppKit
import Combine
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
        XCTAssertEqual(stream.requests.map(requestDescription), ["\(home.path)|name"])

        stream.completeRequest(at: 0, with: .success(entries(["home.txt"], in: home)))

        XCTAssertFalse(model.isLoadingEntries)
        XCTAssertEqual(model.entries.map(\.name), ["home.txt"])
        XCTAssertEqual(model.directorySnapshots, [
            FileBrowserDirectorySnapshot(directory: home.deletingLastPathComponent(), entries: []),
            FileBrowserDirectorySnapshot(directory: home, entries: entries(["home.txt"], in: home))
        ])
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
            "\(missing.path)|name",
            "\(home.path)|name"
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

    func testFirstCharacterCyclingMovesBetweenMatchingRows() {
        let model = makeModel(entries: entries(["alpha.txt", "beta.txt", "build.log", "gamma.txt"]))

        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "beta.txt")
        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "build.log")
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

    func testRightOnFileSetsPaneWobble() {
        let model = makeModel(entries: entries(["file.txt"]))

        model.handle(.right)

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
    }

    func testDirectorySnapshotsIncludeParentCurrentAndSelectedChildContext() {
        let home = URL(fileURLWithPath: "/Users/test")
        let parent = home.deletingLastPathComponent()
        let child = home.appendingPathComponent("Projects", isDirectory: true)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            parent: [directoryEntry(home)],
            home: [directoryEntry(child), fileEntry(home.appendingPathComponent("notes.txt"))],
            child: [fileEntry(child.appendingPathComponent("README.md"))]
        ])
        let model = FileBrowserModel(fileSystem: client, store: InMemoryFileBrowserStore(state: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: home,
            sort: .name,
            traversalChain: []
        )), directoryStream: ImmediateDirectoryStream(fileSystem: client))

        XCTAssertEqual(model.directorySnapshots.map(\.directory), [parent, home, child])
        XCTAssertEqual(model.directorySnapshots[1].entries.map(\.name), ["Projects", "notes.txt"])
        XCTAssertEqual(model.directorySnapshots[2].entries.map(\.name), ["README.md"])
    }

    func testEntryLookupFindsMetadataFromDirectorySnapshots() {
        let home = URL(fileURLWithPath: "/Users/test")
        let child = home.appendingPathComponent("Projects", isDirectory: true)
        let readme = child.appendingPathComponent("README.md")
        let modifiedAt = Date(timeIntervalSince1970: 1_234)
        let client = StubFileSystemClient(home: home, entriesByDirectory: [
            home: [directoryEntry(child)],
            child: [FileBrowserEntry(
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

    func testArrowNavigationDoesNotRereadUnchangedParentOrCurrentSnapshots() {
        let home = URL(fileURLWithPath: "/Users/test")
        let parent = home.deletingLastPathComponent()
        let client = RecordingFileSystemClient(home: home, entriesByDirectory: [
            parent: [directoryEntry(home)],
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

    func testAlphaSelectionRefreshesSelectedChildSnapshot() {
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
        XCTAssertEqual(model.directorySnapshots.last?.directory, archive)
        XCTAssertEqual(model.directorySnapshots.last?.entries.map(\.name), ["archive.txt"])
    }

    private func makeModel(
        entries: [FileBrowserEntry] = [],
        persisted: FileBrowserPersistedState = .defaultValue,
        home: URL = URL(fileURLWithPath: "/Users/test"),
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
        home: URL = URL(fileURLWithPath: "/Users/test"),
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

    private func fileEntry(_ url: URL) -> FileBrowserEntry {
        FileBrowserEntry(url: url, kind: .file, size: 1, createdAt: nil, modifiedAt: nil, isHidden: false)
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

    private func requestDescription(_ request: (directory: URL, sort: FileBrowserSort)) -> String {
        "\(request.directory.path)|\(request.sort.rawValue)"
    }
}
