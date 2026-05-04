import XCTest
@testable import Bucky

final class ToolResultsSnapshotPolicyTests: XCTestCase {
    func testBlankCalculatorQueryUpdatesImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .calculator, query: "   "),
            .immediate
        )
    }

    func testCalculatorQueriesUpdateImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .calculator, query: "2 + 2"),
            .immediate
        )
    }

    func testDictionaryQueriesUpdateImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .dictionary, query: "hello"),
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
            ToolResultsSnapshotPolicy.animation(for: .dictionary, items: items),
            .subtle
        )
    }

    func testApplicationAndCalculationSnapshotsDoNotUseDictionarySnapshotAnimation() {
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
            ToolResultsSnapshotPolicy.animation(for: .calculator, items: calculationItems),
            .none
        )
    }
}
