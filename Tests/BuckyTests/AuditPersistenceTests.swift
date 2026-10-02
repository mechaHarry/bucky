import Foundation
import XCTest
@testable import Bucky

final class AuditPersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PersistenceAudit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testPrivatePermissionsAndExistingAncestorPermissionsArePreserved() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("owned/nested/value.json")
        try JSONFilePersistence.write(["value"], to: file)
        for path in [file.deletingLastPathComponent(), file.deletingLastPathComponent().deletingLastPathComponent()] {
            XCTAssertEqual(try permissions(path), 0o700)
        }
        XCTAssertEqual(try permissions(file), 0o600)
        XCTAssertEqual(try permissions(directory), 0o755)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try JSONFilePersistence.write(["updated"], to: file)
        XCTAssertEqual(try permissions(file), 0o600)
    }

    func testEncodingFailurePreservesPreviousFile() throws {
        let file = directory.appendingPathComponent("value.json")
        try JSONFilePersistence.write(["original"], to: file)
        let original = try Data(contentsOf: file)
        XCTAssertThrowsError(try JSONFilePersistence.write(Double.infinity, to: file))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor func testAsyncHelperCanCallSyncHelperOnWorkerWithoutDeadlock() async throws {
        let file = directory.appendingPathComponent("value.json")
        try await JSONFilePersistence.perform {
            try JSONFilePersistence.write(["nested"], to: file)
        }
        let value = try await JSONFilePersistence.readAsync([String].self, from: file)
        XCTAssertEqual(value, ["nested"])
    }

    @MainActor func testAsyncWriteUsesDefaultsAndPropagatesFailures() async throws {
        let file = directory.appendingPathComponent("value.json")
        try await JSONFilePersistence.writeAsync(["original"], to: file)
        let original = try Data(contentsOf: file)
        do {
            try await JSONFilePersistence.writeAsync(Double.infinity, to: file)
            XCTFail("Encoding failure must propagate")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try permissions(file), 0o600)
    }

    func testCorruptInclusionReloadPreservesLastValidStateAndFile() throws {
        let file = directory.appendingPathComponent("inclusions.json")
        let store = InclusionStore(fileURL: file)
        XCTAssertTrue(store.add(path: "/Applications/Example.app"))
        let corrupt = Data("malformed".utf8)
        try corrupt.write(to: file)
        XCTAssertFalse(store.load())
        XCTAssertEqual(store.includedPaths, ["/Applications/Example.app"])
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.remove(path: "/Applications/Example.app"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testInclusionAndExclusionFailureDoNotPublishMutation() throws {
        let file = directory.appendingPathComponent("inclusions.json")
        let inclusions = InclusionStore(fileURL: file)
        XCTAssertTrue(inclusions.add(path: "/Applications/Example.app"))
        // Replacing the backing file with a directory makes atomic replacement fail deterministically.
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(inclusions.add(path: "/Applications/Other.app"))
        XCTAssertEqual(inclusions.includedPaths, ["/Applications/Example.app"])
        XCTAssertNotNil(inclusions.lastError)

        let exclusionFile = directory.appendingPathComponent("exclusions.json")
        let exclusions = ExclusionStore(fileURL: exclusionFile)
        let app = item(url: URL(fileURLWithPath: "/Applications/Example.app"))
        XCTAssertTrue(exclusions.exclude(app))
        try FileManager.default.removeItem(at: exclusionFile)
        try FileManager.default.createDirectory(at: exclusionFile, withIntermediateDirectories: false)
        XCTAssertFalse(exclusions.remove(path: app.url.path))
        XCTAssertTrue(exclusions.isExcluded(app))
    }

    func testTypedActionExclusionAndLegacyEmptyPathNeverHideAllActions() throws {
        let file = directory.appendingPathComponent("exclusions.json")
        try JSONFilePersistence.write(ExclusionsFile(excludedPaths: ["", "/Applications/Example.app"]), to: file)
        let store = ExclusionStore(fileURL: file)
        let first = item(url: URL(string: "bucky-action://00000000-0000-0000-0000-000000000001")!, target: .shellCommand("true"))
        let second = item(url: URL(string: "bucky-action://00000000-0000-0000-0000-000000000002")!, target: .shellCommand("true"))
        XCTAssertFalse(store.isExcluded(first))
        XCTAssertFalse(store.isExcluded(second))
        XCTAssertTrue(store.exclude(first))
        XCTAssertTrue(store.isExcluded(first))
        XCTAssertFalse(store.isExcluded(second))
        let edited = item(url: first.url, target: .shellCommand("printf example"))
        XCTAssertTrue(store.isExcluded(edited))
        let reloaded = ExclusionStore(fileURL: file)
        XCTAssertTrue(reloaded.isExcluded(first))
        XCTAssertTrue(reloaded.isExcluded(item(url: URL(fileURLWithPath: "/Applications/Example.app"))))
        XCTAssertTrue(reloaded.excludedPaths.contains(""))
        let key = try XCTUnwrap(reloaded.sortedPaths().first { $0.hasPrefix("identity:") })
        XCTAssertTrue(reloaded.remove(path: key))
        XCTAssertFalse(reloaded.isExcluded(first))
    }

    func testSettingsAndHistoryFailureKeepPreviousStateAndExposeSafeErrors() throws {
        let settingsFile = directory.appendingPathComponent("settings.json")
        let settings = SettingsStore(fileURL: settingsFile)
        XCTAssertTrue(settings.updateCustomActions([CustomAction(name: "Example", command: "true")]))
        try FileManager.default.removeItem(at: settingsFile)
        try FileManager.default.createDirectory(at: settingsFile, withIntermediateDirectories: false)
        XCTAssertFalse(settings.updateCustomActions([]))
        XCTAssertEqual(settings.settings.customActions.map(\.name), ["Example"])
        XCTAssertFalse(try XCTUnwrap(settings.lastError).contains(directory.path))

        let historyFile = directory.appendingPathComponent("history.json")
        let history = DictionaryHistoryStore(fileURL: historyFile)
        XCTAssertTrue(history.add(term: "example"))
        try FileManager.default.removeItem(at: historyFile)
        try FileManager.default.createDirectory(at: historyFile, withIntermediateDirectories: false)
        XCTAssertFalse(history.remove(term: "example"))
        XCTAssertEqual(history.words.map(\.term), ["example"])
        XCTAssertNotNil(history.lastError)
    }

    @MainActor func testAsyncLoadsPreserveLastValidStateAndRecoverAfterRepair() async throws {
        let file = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: file)
        let saved = await store.updateAnimationTimingAsync(.smooth)
        XCTAssertTrue(saved)
        try Data("malformed".utf8).write(to: file)
        let loaded = await store.loadAsync()
        XCTAssertFalse(loaded)
        XCTAssertEqual(store.settings.animationTiming, .smooth)
        let refused = await store.updateAnimationTimingAsync(.snappy)
        XCTAssertFalse(refused)
        try JSONFilePersistence.write(BuckySettings.defaultValue, to: file)
        let repaired = await store.loadAsync()
        XCTAssertTrue(repaired)
        XCTAssertNil(store.lastError)
    }

    @MainActor func testCalculationHistoryAsyncAddClearAndFailureRollback() async throws {
        let file = directory.appendingPathComponent("calculations.json")
        let store = CalculationHistoryStore(fileURL: file)
        let saved = await store.addAsync(expression: "1 + 1", result: "2")
        XCTAssertTrue(saved)
        XCTAssertEqual(store.calculations.map(\.result), ["2"])
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let cleared = await store.clearAsync()
        XCTAssertFalse(cleared)
        XCTAssertEqual(store.calculations.map(\.result), ["2"])
        XCTAssertNotNil(store.lastError)
    }

    @MainActor func testAsyncInclusionAndExclusionReadFailuresPreserveLastValidState() async throws {
        let inclusionFile = directory.appendingPathComponent("inclusions.json")
        let inclusions = InclusionStore(fileURL: inclusionFile)
        let added = await inclusions.addAsync(paths: ["/Applications/Example.app"])
        XCTAssertTrue(added)
        try Data("malformed".utf8).write(to: inclusionFile)
        let inclusionLoaded = await inclusions.loadAsync()
        XCTAssertFalse(inclusionLoaded)
        XCTAssertEqual(inclusions.includedPaths, ["/Applications/Example.app"])
        XCTAssertNotNil(inclusions.lastError)
        let removed = await inclusions.removeAsync(path: "/Applications/Example.app")
        XCTAssertFalse(removed)

        let exclusionFile = directory.appendingPathComponent("exclusions.json")
        let exclusions = ExclusionStore(fileURL: exclusionFile)
        let app = item(url: URL(fileURLWithPath: "/Applications/Example.app"))
        let excluded = await exclusions.excludeAsync(app)
        XCTAssertTrue(excluded)
        try Data("malformed".utf8).write(to: exclusionFile)
        let exclusionLoaded = await exclusions.loadAsync()
        XCTAssertFalse(exclusionLoaded)
        XCTAssertTrue(exclusions.isExcluded(app))
        XCTAssertNotNil(exclusions.lastError)
    }

    func testSnapshotUsesPrivatePermissions() throws {
        let file = directory.appendingPathComponent("owned/snapshot.json")
        let cache = ApplicationIndexSnapshotCache(fileURL: file)
        let app = item(url: URL(fileURLWithPath: "/Applications/Example.app"))
        cache.save([app])
        XCTAssertEqual(cache.load(), [app])
        XCTAssertEqual(try permissions(file), 0o600)
        XCTAssertEqual(try permissions(file.deletingLastPathComponent()), 0o700)
    }

    private func permissions(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber).intValue & 0o777
    }
    private func item(url: URL, target: LaunchTarget? = nil) -> LaunchItem {
        LaunchItem(title: "Example", subtitle: "", url: url, launchTarget: target, searchText: "example")
    }
}
