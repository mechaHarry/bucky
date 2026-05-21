import XCTest
@testable import Bucky

final class InclusionExclusionStoresTests: XCTestCase {
    func testInclusionStoreDoesNotHardcodeFinderAsDefaultInclusion() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Bucky/Settings/InclusionExclusionStores.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("/System/Library/CoreServices/Finder.app"))
    }
}
