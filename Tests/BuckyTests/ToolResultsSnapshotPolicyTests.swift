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

    func testNonBlankQueriesUseCatalogUpdatePolicies() {
        for mode in LauncherMode.ordered {
            XCTAssertEqual(
                ToolResultsSnapshotPolicy.update(for: mode, query: "hello"),
                mode.stoneDefinition.updatePolicy
            )
        }
    }

    func testBlankQueriesUpdateImmediatelyForEveryMode() {
        for mode in LauncherMode.ordered {
            XCTAssertEqual(
                ToolResultsSnapshotPolicy.update(for: mode, query: "   "),
                .immediate
            )
        }
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
