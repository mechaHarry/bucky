import XCTest
@testable import Bucky

final class ArithmeticEvaluatorTests: XCTestCase {
    func testInt64BoundaryFormattingNeverTraps() {
        XCTAssertNotNil(ArithmeticEvaluator.evaluate("9223372036854775807"))
        XCTAssertNotNil(ArithmeticEvaluator.evaluate("9223372036854775808"))
        XCTAssertEqual(ArithmeticEvaluator.evaluate("-9223372036854775808"), "-9223372036854775808")
        XCTAssertNotNil(ArithmeticEvaluator.evaluate("-9223372036854777856"))
    }

    func testInputAndRecursionLimitsRejectResourceExhaustion() {
        XCTAssertNil(ArithmeticEvaluator.evaluate(String(repeating: "-", count: 1000) + "1"))
        XCTAssertNil(ArithmeticEvaluator.evaluate(String(repeating: "(", count: 1000) + "1" + String(repeating: ")", count: 1000)))
        XCTAssertNil(ArithmeticEvaluator.evaluate(String(repeating: "1", count: ArithmeticEvaluator.maximumInputLength + 1)))
        XCTAssertEqual(ArithmeticEvaluator.evaluate(String(repeating: "(", count: 12) + "2+3" + String(repeating: ")", count: 12)), "5")
        XCTAssertNil(ArithmeticEvaluator.evaluate("1/0"))
    }

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
