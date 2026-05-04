import XCTest
@testable import Bucky

final class ToolResultsSnapshotPolicyTests: XCTestCase {
    func testBlankToolsQueryUpdatesImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .tools, query: "   "),
            .immediate
        )
    }

    func testArithmeticToolsQueryUpdatesImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .tools, query: "2 + 2"),
            .immediate
        )
    }

    func testDictionaryToolsQueryUpdatesImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .tools, query: "hello"),
            .immediate
        )
    }

    func testApplicationQueriesUpdateImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .applications, query: "hello"),
            .immediate
        )
    }

    func testDictionaryToolSnapshotsUseSubtleAnimation() {
        let items = [
            ToolItem(
                title: "hello",
                subtitle: "A greeting",
                copyText: nil,
                kind: .dictionary
            )
        ]

        XCTAssertEqual(
            ToolResultsSnapshotPolicy.animation(for: .tools, items: items),
            .subtle
        )
    }

    func testApplicationAndCalculationSnapshotsDoNotUseToolSnapshotAnimation() {
        let calculationItems = [
            ToolItem(
                title: "4",
                subtitle: "2 + 2 =",
                copyText: "4",
                kind: .calculation
            )
        ]

        XCTAssertEqual(
            ToolResultsSnapshotPolicy.animation(for: .applications, items: calculationItems),
            .none
        )
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.animation(for: .tools, items: calculationItems),
            .none
        )
    }
}
