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

    func testFileBrowserStartDirectoryCanBeStored() {
        var settings = BuckySettings.defaultValue
        let startDirectory = URL(fileURLWithPath: "/Users/test/Documents")

        settings.fileBrowserStartDirectory = startDirectory

        XCTAssertEqual(settings.fileBrowserStartDirectory, startDirectory)
    }
}
