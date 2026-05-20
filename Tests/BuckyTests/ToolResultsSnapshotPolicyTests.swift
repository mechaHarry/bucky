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

    func testDictionaryQueriesUseDeferredSnapshotUpdate() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .dictionary, query: "hello"),
            .deferred(delayNanoseconds: ToolResultsSnapshotPolicy.dictionaryLookupDelayNanoseconds)
        )
    }

    func testBlankDictionaryQueriesUpdateImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .dictionary, query: "   "),
            .immediate
        )
    }

    func testApplicationQueriesUseDeferredSnapshotUpdate() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .applications, query: "hello"),
            .deferred(delayNanoseconds: ToolResultsSnapshotPolicy.applicationFilterDelayNanoseconds)
        )
    }

    func testBlankApplicationQueriesUpdateImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .applications, query: "   "),
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
