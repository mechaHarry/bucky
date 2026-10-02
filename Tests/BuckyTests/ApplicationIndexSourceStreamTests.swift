import XCTest
@testable import Bucky

final class ApplicationIndexSourceStreamTests: XCTestCase {
    func testIncludedAppsAddParentCoverageAndDeduplicateParents() {
        let urls = ApplicationIndexWatchPolicy.watchURLs(
            applicationRoots: [],
            includedPaths: ["/tmp/Examples/First.app", "/tmp/Examples/Second.app"],
            appSupportDirectory: URL(fileURLWithPath: "/tmp/Config"),
            systemSettingsResourcesDirectory: URL(fileURLWithPath: "/tmp/Resources"),
            systemSettingsExtensionRoots: [])
        XCTAssertEqual(urls.map(\.path), ["/tmp/Resources", "/tmp/Config", "/tmp/Examples"])
        XCTAssertTrue(ApplicationIndexWatchPolicy.shouldTriggerChange(
            eventPath: "/tmp/Examples/First.app/Contents/Info.plist", watchURLs: urls))
    }

    func testMissingRootsUseNearestExistingAncestorWithoutCreatingDirectories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SourceAudit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing/nested")
        XCTAssertEqual(ApplicationIndexWatchPolicy.existingWatchURLs(for: [missing]).map(\.path), [directory.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertTrue(ApplicationIndexWatchPolicy.shouldTriggerChange(eventPath: directory.path, watchURLs: [missing]))
        let unrelated = directory.appendingPathComponent("unrelated").path
        XCTAssertFalse(ApplicationIndexWatchPolicy.shouldTriggerChange(eventPath: unrelated, watchURLs: [missing]))
    }

    func testWatchPolicyIncludesApplicationSettingsAndConfigurationSources() {
        let appRoot = URL(fileURLWithPath: "/tmp/Applications", isDirectory: true)
        let coreServicesRoot = URL(fileURLWithPath: "/tmp/CoreServices", isDirectory: true)
        let appSupportDirectory = URL(fileURLWithPath: "/tmp/Bucky", isDirectory: true)
        let settingsResourcesDirectory = URL(fileURLWithPath: "/tmp/SystemSettings/Resources", isDirectory: true)
        let extensionRoot = URL(fileURLWithPath: "/tmp/ExtensionKit", isDirectory: true)

        let urls = ApplicationIndexWatchPolicy.watchURLs(
            applicationRoots: [appRoot, coreServicesRoot],
            appSupportDirectory: appSupportDirectory,
            systemSettingsResourcesDirectory: settingsResourcesDirectory,
            systemSettingsExtensionRoots: [extensionRoot]
        )

        XCTAssertEqual(urls.map(\.path), [
            appRoot.path,
            coreServicesRoot.path,
            settingsResourcesDirectory.path,
            extensionRoot.path,
            appSupportDirectory.path
        ])
    }

    func testWatchPolicyRemovesDuplicateSourcesWithoutReordering() {
        let appRoot = URL(fileURLWithPath: "/tmp/Applications", isDirectory: true)
        let appSupportDirectory = URL(fileURLWithPath: "/tmp/Bucky", isDirectory: true)

        let urls = ApplicationIndexWatchPolicy.watchURLs(
            applicationRoots: [appRoot, appRoot],
            appSupportDirectory: appSupportDirectory,
            systemSettingsResourcesDirectory: appRoot,
            systemSettingsExtensionRoots: [appSupportDirectory]
        )

        XCTAssertEqual(urls.map(\.path), [
            appRoot.path,
            appSupportDirectory.path
        ])
    }

    func testSourceStreamUsesBackgroundUtilityQueuePolicy() {
        XCTAssertEqual(
            ApplicationIndexSourceStreamPolicy.queueLabel,
            "local.bucky.application-index-source-stream"
        )
        XCTAssertEqual(ApplicationIndexSourceStreamPolicy.queueQoS, .utility)
    }

    func testWatchPolicyIgnoresMemoizedSnapshotWrites() {
        let appRoot = URL(fileURLWithPath: "/tmp/Applications", isDirectory: true)
        let appSupportDirectory = URL(fileURLWithPath: "/tmp/Bucky", isDirectory: true)
        let watchURLs = ApplicationIndexWatchPolicy.watchURLs(
            applicationRoots: [appRoot],
            appSupportDirectory: appSupportDirectory,
            systemSettingsResourcesDirectory: appRoot,
            systemSettingsExtensionRoots: []
        )

        XCTAssertFalse(ApplicationIndexWatchPolicy.shouldTriggerChange(
            eventPath: appSupportDirectory.appendingPathComponent("app-index-snapshot.json").path,
            watchURLs: watchURLs,
            appSupportDirectory: appSupportDirectory
        ))
        XCTAssertFalse(ApplicationIndexWatchPolicy.shouldTriggerChange(
            eventPath: appSupportDirectory.path,
            watchURLs: watchURLs,
            appSupportDirectory: appSupportDirectory
        ))
    }

    func testWatchPolicyKeepsIndexAffectingConfigurationWrites() {
        let appRoot = URL(fileURLWithPath: "/tmp/Applications", isDirectory: true)
        let appSupportDirectory = URL(fileURLWithPath: "/tmp/Bucky", isDirectory: true)
        let watchURLs = ApplicationIndexWatchPolicy.watchURLs(
            applicationRoots: [appRoot],
            appSupportDirectory: appSupportDirectory,
            systemSettingsResourcesDirectory: appRoot,
            systemSettingsExtensionRoots: []
        )

        XCTAssertTrue(ApplicationIndexWatchPolicy.shouldTriggerChange(
            eventPath: appSupportDirectory.appendingPathComponent("settings.json").path,
            watchURLs: watchURLs,
            appSupportDirectory: appSupportDirectory
        ))
        XCTAssertTrue(ApplicationIndexWatchPolicy.shouldTriggerChange(
            eventPath: appSupportDirectory.appendingPathComponent("inclusions.json").path,
            watchURLs: watchURLs,
            appSupportDirectory: appSupportDirectory
        ))
        XCTAssertTrue(ApplicationIndexWatchPolicy.shouldTriggerChange(
            eventPath: appSupportDirectory.appendingPathComponent("exclusions.json").path,
            watchURLs: watchURLs,
            appSupportDirectory: appSupportDirectory
        ))
    }

    func testWatchPolicyKeepsApplicationRootChanges() {
        let appRoot = URL(fileURLWithPath: "/tmp/Applications", isDirectory: true)
        let appSupportDirectory = URL(fileURLWithPath: "/tmp/Bucky", isDirectory: true)
        let watchURLs = ApplicationIndexWatchPolicy.watchURLs(
            applicationRoots: [appRoot],
            appSupportDirectory: appSupportDirectory,
            systemSettingsResourcesDirectory: appRoot,
            systemSettingsExtensionRoots: []
        )

        XCTAssertTrue(ApplicationIndexWatchPolicy.shouldTriggerChange(
            eventPath: appRoot.appendingPathComponent("Example.app").path,
            watchURLs: watchURLs,
            appSupportDirectory: appSupportDirectory
        ))
    }
}
