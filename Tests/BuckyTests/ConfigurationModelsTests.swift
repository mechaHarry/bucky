import XCTest
@testable import Bucky

final class ConfigurationModelsTests: XCTestCase {
    func testBuckySettingsDefaultFileBrowserStartDirectoryUsesHomeFallback() {
        XCTAssertNil(BuckySettings.defaultValue.fileBrowserStartDirectory)
    }

    func testBuckySettingsDecodesMissingFileBrowserStartDirectoryAsNil() throws {
        let data = Data(#"{"launchAtStartup":false}"#.utf8)

        let settings = try JSONDecoder().decode(BuckySettings.self, from: data)

        XCTAssertNil(settings.fileBrowserStartDirectory)
    }

    func testBuckySettingsDecodesMissingCustomActionsAsEmpty() throws {
        let data = Data(#"{"launchAtStartup":false}"#.utf8)

        let settings = try JSONDecoder().decode(BuckySettings.self, from: data)

        XCTAssertEqual(settings.customActions, [])
    }

    func testFileBrowserStartDirectoryCanBeStored() {
        var settings = BuckySettings.defaultValue
        let startDirectory = URL(fileURLWithPath: "/Users/test/Documents")

        settings.fileBrowserStartDirectory = startDirectory

        XCTAssertEqual(settings.fileBrowserStartDirectory, startDirectory)
    }

    func testCustomActionsCanBeStored() throws {
        let action = CustomAction(
            name: "Build Docs",
            command: "make docs"
        )
        var settings = BuckySettings.defaultValue

        settings.customActions = [action]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(BuckySettings.self, from: data)
        XCTAssertEqual(decoded.customActions, [action])
    }
}
