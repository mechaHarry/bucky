import XCTest
@testable import Bucky

final class ToolResultsSnapshotPolicyTests: XCTestCase {
    func testCalculatorRouteInApplicationsUpdatesImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .applications, query: "=2 + 2"),
            .immediate
        )
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .applications, query: "   =2 + 2"),
            .immediate
        )
    }

    func testDictionaryRouteInApplicationsUsesDeferredSnapshotUpdate() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .applications, query: "?hello"),
            .deferred(delayNanoseconds: ToolResultsSnapshotPolicy.dictionaryLookupDelayNanoseconds)
        )
    }

    func testEmptyDictionaryRouteInApplicationsUpdatesImmediately() {
        XCTAssertEqual(
            ToolResultsSnapshotPolicy.update(for: .applications, query: "?"),
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
            ToolResultsSnapshotPolicy.animation(for: .applications, items: items),
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
    }
}
