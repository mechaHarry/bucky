import XCTest
@testable import Bucky

final class ArithmeticEvaluatorTests: XCTestCase {
    func testTrailingEqualsCompletesExpression() {
        XCTAssertEqual(ArithmeticEvaluator.normalizedExpression("2 + 2 ="), "2 + 2")
        XCTAssertEqual(ArithmeticEvaluator.normalizedExpression("2 + 2=="), "2 + 2")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("2 + 2 ="), "4")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("1,200 / 3 ="), "400")
    }

    func testEmbeddedEqualsRemainsInvalid() {
        XCTAssertNil(ArithmeticEvaluator.evaluate("2 = + 2"))
        XCTAssertFalse(ArithmeticEvaluator.isArithmeticInput("2 = + 2"))
    }

    func testHistoryStorageUsesNormalizedExpression() {
        XCTAssertTrue(ArithmeticEvaluator.shouldStoreInHistory("2 + 2 ="))
        XCTAssertFalse(ArithmeticEvaluator.shouldStoreInHistory("42 ="))
    }
}
