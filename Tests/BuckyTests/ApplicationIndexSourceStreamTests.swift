import XCTest
@testable import Bucky

final class ApplicationIndexSourceStreamTests: XCTestCase {
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
            "com.bucky.bucky.application-index-source-stream"
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
