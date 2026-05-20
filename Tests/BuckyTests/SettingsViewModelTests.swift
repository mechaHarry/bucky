import XCTest
@testable import Bucky

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckySettingsViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testAddsCustomActionAndSignalsSettingsChanged() {
        var settingsChangedCount = 0
        let store = SettingsStore(fileURL: temporaryDirectory.appendingPathComponent("settings.json"))
        let model = makeModel(settingsStore: store) {
            settingsChangedCount += 1
        }

        model.customActionName = "Build Docs"
        model.customActionCommand = "make docs"
        model.saveCustomAction()

        XCTAssertEqual(model.customActions.map(\.name), ["Build Docs"])
        XCTAssertEqual(store.settings.customActions.map(\.command), ["make docs"])
        XCTAssertEqual(settingsChangedCount, 1)
        XCTAssertEqual(model.customActionName, "")
        XCTAssertEqual(model.customActionCommand, "")
    }

    func testSelectingCustomActionLoadsEditableFieldsAndRemoveDeletesIt() {
        let action = CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Build Docs",
            command: "make docs"
        )
        let store = SettingsStore(fileURL: temporaryDirectory.appendingPathComponent("settings.json"))
        store.updateCustomActions([action])
        let model = makeModel(settingsStore: store)
        model.refresh()

        model.selectedCustomActionID = action.id
        model.selectCustomAction(action.id)

        XCTAssertEqual(model.customActionName, "Build Docs")
        XCTAssertEqual(model.customActionCommand, "make docs")

        model.removeSelectedCustomAction()

        XCTAssertEqual(model.customActions, [])
        XCTAssertEqual(store.settings.customActions, [])
        XCTAssertNil(model.selectedCustomActionID)
    }

    private func makeModel(
        settingsStore: SettingsStore,
        settingsChangedHandler: @escaping () -> Void = {}
    ) -> SettingsViewModel {
        SettingsViewModel(
            settingsStore: settingsStore,
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            hotKeyChangeHandler: { _ in true },
            inclusionsChangedHandler: {},
            exclusionsChangedHandler: {},
            settingsChangedHandler: settingsChangedHandler
        )
    }
}
