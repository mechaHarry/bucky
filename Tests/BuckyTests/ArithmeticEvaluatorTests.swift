import XCTest
@testable import Bucky

final class ArithmeticEvaluatorTests: XCTestCase {
    func testTrailingEqualsCompletesExpression() {
        XCTAssertEqual(ArithmeticEvaluator.normalizedExpression("2 + 2 ="), "2 + 2")
        XCTAssertEqual(ArithmeticEvaluator.normalizedExpression("2 + 2=="), "2 + 2")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("2 + 2 ="), "4")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("1,200 / 3 ="), "400")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("109109100 + 1"), "109,109,101")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("1 / 4"), "0.25")
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
