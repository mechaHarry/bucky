import AppKit
import XCTest
@testable import Bucky

@MainActor
final class FileBrowserConcurrencyTests: XCTestCase {
    func testModelFlushWaitsForConfirmedOperationThenStoreDurabilityBarrier() async {
        let home = URL(fileURLWithPath: "/tmp/files-fixture", isDirectory: true)
        let store = ManualFlushFileBrowserStore()
        let worker = ManualFileBrowserWorker()
        let services = RecordingFileBrowserServices()
        let model = FileBrowserModel(fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
                                     store: store, directoryStream: ImmediateDirectoryStream(), directoryObserver: nil,
                                     fileServices: services, operationWorker: worker)
        let url = home.appendingPathComponent("sample.txt")
        model.addSelectedURLForTesting(url)
        model.requestTrashConfirmation()
        model.handle(.open)
        model.handle(.open)
        XCTAssertTrue(model.isPerformingOperation)
        let requestedFlush = expectation(description: "store flush requested after operation")
        store.onFlush = { requestedFlush.fulfill() }
        var completed = false
        model.flushPersistence { completed = true }
        await Task.yield()
        XCTAssertNil(store.pendingFlush)
        XCTAssertFalse(completed)
        worker.completeNext()
        await fulfillment(of: [requestedFlush], timeout: 2)
        XCTAssertEqual(services.events, [.trash([url])])
        XCTAssertFalse(completed)
        store.pendingFlush?()
        XCTAssertTrue(completed)
    }
    func testModelFlushWaitsForStoreDurabilityBarrier() {
        let home = URL(fileURLWithPath: "/tmp/files-fixture", isDirectory: true)
        let store = ManualFlushFileBrowserStore()
        let model = FileBrowserModel(fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
                                     store: store, directoryStream: ImmediateDirectoryStream(), directoryObserver: nil)
        var completed = false
        model.flushPersistence { completed = true }
        XCTAssertFalse(completed)
        store.pendingFlush?()
        XCTAssertTrue(completed)
    }
    func testCancellationInvokesInstalledActionOnceAndReleasesItsCaptures() {
        var calls = 0
        let cancellation = FileBrowserCancellation { calls += 1 }
        cancellation.cancel()
        cancellation.cancel()
        XCTAssertEqual(calls, 1)
        var lateCalls = 0
        cancellation.setCancelAction { lateCalls += 1 }
        XCTAssertEqual(lateCalls, 1)

        weak var weakTarget: NSObject?
        let handle = FileBrowserCancellation()
        do {
            let target = NSObject()
            weakTarget = target
            handle.setCancelAction { _ = target }
        }
        XCTAssertNotNil(weakTarget)
        handle.cancel()
        XCTAssertNil(weakTarget)
    }
    func testOperationRunsOffMainActorAndCompletesOnMainActor() async {
        let worker = FileBrowserWorker()
        let done = expectation(description: "operation completed")
        worker.run({ Thread.isMainThread }) { result in
            XCTAssertEqual(try? result.get(), false)
            XCTAssertTrue(Thread.isMainThread)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)
    }

    func testLatestDirectoryRequestCoalescesQueuedScans() async {
        let queue = DispatchQueue(label: "test.files.scan")
        queue.suspend()
        let home = URL(fileURLWithPath: "/tmp/files-fixture", isDirectory: true)
        let fileSystem = RecordingFileSystemClient(home: home, entriesByDirectory: [:])
        let stream = FileBrowserDirectoryStream(fileSystem: fileSystem, queue: queue)
        let done = expectation(description: "latest scan")
        for index in 0..<100 {
            stream.loadEntries(in: home.appendingPathComponent("folder-\(index)", isDirectory: true), sort: .name, foldersFirst: false) { _ in
                XCTAssertEqual(index, 99)
                done.fulfill()
            }
        }
        queue.resume()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(fileSystem.entryRequests.count, 1)
        XCTAssertEqual(fileSystem.entryRequests.first?.directory.lastPathComponent, "folder-99")
    }

    func testInactiveObservationCancelsRefreshAndResumesOnce() async throws {
        let home = URL(fileURLWithPath: "/tmp/files-fixture", isDirectory: true)
        let observer = ManualDirectoryObserver()
        let stream = ManualDirectoryStream()
        let model = FileBrowserModel(fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
                                     store: InMemoryFileBrowserStore(state: .defaultValue),
                                     directoryStream: stream, directoryObserver: observer)
        observer.triggerLatestChange()
        model.setActive(false)
        observer.triggerLatestChange()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(stream.requests.count, 1)
        XCTAssertFalse(model.isLoadingEntries)
        model.setActive(true)
        model.setActive(true)
        XCTAssertEqual(stream.requests.count, 2)
        XCTAssertEqual(observer.observedDirectories.count, 2)
    }

    func testWatcherBurstDebouncesToSingleReload() async throws {
        let home = URL(fileURLWithPath: "/tmp/files-fixture", isDirectory: true)
        let observer = ManualDirectoryObserver()
        let stream = ManualDirectoryStream()
        let model = FileBrowserModel(fileSystem: StubFileSystemClient(home: home, entriesByDirectory: [:]),
                                     store: InMemoryFileBrowserStore(state: .defaultValue),
                                     directoryStream: stream, directoryObserver: observer)
        for _ in 0..<100 { observer.triggerLatestChange() }
        XCTAssertEqual(stream.requests.count, 1)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(stream.requests.count, 2)
        model.setActive(false)
    }

    func testBusyConflictScanPreservesApprovalAndSelectionsUntilTransferCompletes() {
        let worker = ManualFileBrowserWorker()
        let services = RecordingFileBrowserServices()
        let home = URL(fileURLWithPath: "/tmp/files-fixture", isDirectory: true)
        let url = home.appendingPathComponent("sample.txt")
        let entry = FileBrowserEntry(url: url, kind: .file, size: 1, createdAt: nil, modifiedAt: nil, isHidden: false)
        let system = StubFileSystemClient(home: home, entriesByDirectory: [home: [entry]])
        let model = FileBrowserModel(fileSystem: system, store: InMemoryFileBrowserStore(state: .defaultValue),
                                     directoryStream: ImmediateDirectoryStream(fileSystem: system), directoryObserver: nil,
                                     fileServices: services, operationWorker: worker)
        services.conflicts = [FileBrowserConflict(source: url, destination: url)]
        model.handle(.space)
        model.startTransfer(.copy)
        model.handle(.open)
        model.handle(.open)
        XCTAssertTrue(model.isPerformingOperation)
        XCTAssertEqual(model.selectedURLs, [url])
        model.handle(.open)
        XCTAssertEqual(worker.jobs.count, 1)
        worker.completeNext()
        XCTAssertEqual(model.focusedConflictResolution, .keepBoth)
        XCTAssertFalse(model.isPerformingOperation)
        XCTAssertTrue(services.events.isEmpty)
        model.handle(.down)
        model.handle(.open)
        XCTAssertTrue(model.isPerformingOperation)
        XCTAssertEqual(model.selectedURLs, [url])
        worker.completeNext()
        XCTAssertEqual(services.events, [.copy([url], home, .replace)])
        XCTAssertFalse(model.isPerformingOperation)
        XCTAssertEqual(model.focusState, .browse)
        XCTAssertTrue(model.selectedURLs.isEmpty)
    }

    func testAsyncMutationFailureKeepsRecoverableFocusAndSelection() {
        let worker = ManualFileBrowserWorker()
        let services = RecordingFileBrowserServices()
        services.error = TestFileBrowserServiceError.failed
        let home = URL(fileURLWithPath: "/tmp/files-fixture", isDirectory: true)
        let url = home.appendingPathComponent("sample.txt")
        let system = StubFileSystemClient(home: home, entriesByDirectory: [:])
        let model = FileBrowserModel(fileSystem: system, store: InMemoryFileBrowserStore(state: .defaultValue),
                                     directoryStream: ImmediateDirectoryStream(fileSystem: system), directoryObserver: nil,
                                     fileServices: services, operationWorker: worker)
        model.addSelectedURLForTesting(url)
        model.requestTrashConfirmation()
        model.handle(.open)
        XCTAssertTrue(worker.jobs.isEmpty)
        model.handle(.open)
        XCTAssertTrue(model.isPerformingOperation)
        worker.completeNext()
        XCTAssertFalse(model.isPerformingOperation)
        XCTAssertEqual(model.selectedURLs, [url])
        XCTAssertEqual(model.statusMessage, "failed")
        XCTAssertEqual(model.focusState, .confirming(.trash([url], step: 2)))
    }
}

private final class ManualFlushFileBrowserStore: FileBrowserPersisting {
    var state = FileBrowserPersistedState.defaultValue
    var pendingFlush: (() -> Void)?
    var onFlush: (() -> Void)?
    func update(_ nextState: FileBrowserPersistedState) { state = nextState }
    func bookmarkData(for directory: URL) -> Data? { nil }
    func rememberDirectoryAccess(_ directory: URL) {}
    func flush(completion: @escaping () -> Void) {
        pendingFlush = completion
        onFlush?()
    }
}

@MainActor
private final class ManualFileBrowserWorker: FileBrowserWorking {
    var jobs: [() -> Void] = []
    func run<Value>(_ operation: @escaping () throws -> Value, completion: @escaping (Result<Value, Error>) -> Void) {
        jobs.append { completion(Result { try operation() }) }
    }
    func completeNext() { jobs.removeFirst()() }
}
