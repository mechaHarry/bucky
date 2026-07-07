import XCTest
@testable import Bucky

final class ApplicationQueryRouteTests: XCTestCase {
    func testOrdinaryQueryPreservesOriginalText() {
        XCTAssertEqual(
            ApplicationQueryRoute(query: "  visual studio"),
            .applications(query: "  visual studio")
        )
    }

    func testQuestionMarkInOrdinaryQueryStaysApplications() {
        XCTAssertEqual(
            ApplicationQueryRoute(query: "mail?"),
            .applications(query: "mail?")
        )
    }

    func testEqualsMarkerSelectsCalculatorWithEmptyExpression() {
        XCTAssertEqual(
            ApplicationQueryRoute(query: "="),
            .calculator(expression: "")
        )
    }

    func testEqualsMarkerTrimsCalculatorExpression() {
        XCTAssertEqual(
            ApplicationQueryRoute(query: "  = 1 + 2 "),
            .calculator(expression: "1 + 2")
        )
    }

    func testQuestionMarkSelectsDictionaryWithEmptyTerm() {
        XCTAssertEqual(
            ApplicationQueryRoute(query: "?"),
            .dictionary(term: "")
        )
    }

    func testQuestionMarkTrimsDictionaryTerm() {
        XCTAssertEqual(
            ApplicationQueryRoute(query: "  ? someWord "),
            .dictionary(term: "someWord")
        )
    }
}
