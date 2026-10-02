import XCTest
@testable import Bucky

@MainActor
final class AuditSettingsViewModelTests: XCTestCase {
    func testAsyncSaveFailureKeepsDraftAndDoesNotSignalChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsAudit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsFile = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: settingsFile)
        let action = CustomAction(name: "Example", command: "true")
        XCTAssertTrue(store.updateCustomActions([action]))
        var changed = 0
        let model = SettingsViewModel(
            settingsStore: store,
            inclusionStore: InclusionStore(fileURL: directory.appendingPathComponent("inclusions.json")),
            exclusionStore: ExclusionStore(fileURL: directory.appendingPathComponent("exclusions.json")),
            hotKeyChangeHandler: { _ in true },
            inclusionsChangedHandler: {}, exclusionsChangedHandler: {},
            settingsChangedHandler: { changed += 1 })
        await model.refreshAsync()
        model.selectCustomAction(action.id)
        model.customActionName = "Edited example"
        model.customActionCommand = "printf example"
        try FileManager.default.removeItem(at: settingsFile)
        try FileManager.default.createDirectory(at: settingsFile, withIntermediateDirectories: false)
        await model.saveCustomActionAsync()
        XCTAssertEqual(model.customActionName, "Edited example")
        XCTAssertEqual(model.customActionCommand, "printf example")
        XCTAssertEqual(model.selectedCustomActionID, action.id)
        XCTAssertEqual(model.customActions, [action])
        XCTAssertEqual(store.settings.customActions, [action])
        XCTAssertEqual(changed, 0)
        XCTAssertNotNil(model.errorMessage)
        await model.removeSelectedCustomActionAsync()
        XCTAssertEqual(model.selectedCustomActionID, action.id)
        XCTAssertEqual(model.customActions, [action])
        XCTAssertEqual(changed, 0)
    }
}
