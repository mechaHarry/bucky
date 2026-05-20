import XCTest
@testable import Bucky

final class CustomActionIndexerTests: XCTestCase {
    func testIndexesNamedCommandsAsActionLaunchItems() {
        let action = CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Build Docs",
            command: "make docs"
        )

        let items = CustomActionIndexer().load(actions: [action])

        XCTAssertEqual(items.map(\.title), ["Build Docs"])
        XCTAssertEqual(items.first?.subtitle, "make docs")
        XCTAssertEqual(items.first?.category, .action)
        XCTAssertEqual(items.first?.launchTarget, .shellCommand("make docs"))
        XCTAssertEqual(items.first?.url.absoluteString, "bucky-action://00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(items.first?.searchText, "build docs make docs")
    }

    func testSkipsBlankNamesAndCommands() {
        let actions = [
            CustomAction(name: "", command: "make docs"),
            CustomAction(name: "Build Docs", command: "   ")
        ]

        XCTAssertEqual(CustomActionIndexer().load(actions: actions), [])
    }
}
