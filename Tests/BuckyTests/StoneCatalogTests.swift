import XCTest
@testable import Bucky

final class StoneCatalogTests: XCTestCase {
    func testCatalogContainsEveryStoneIDExactlyOnce() {
        XCTAssertEqual(StoneCatalog.orderedDefinitions.map(\.id), StoneID.allCases)
    }

    func testCatalogIDsAndShortcutNumbersAreUniqueAndStable() {
        let ids = StoneCatalog.orderedDefinitions.map(\.id.rawValue)
        let shortcutNumbers = StoneCatalog.orderedDefinitions.map(\.shortcutNumber)

        XCTAssertEqual(ids, [1, 2, 3, 4])
        XCTAssertEqual(shortcutNumbers, [1, 2, 3, 4])
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(shortcutNumbers).count, shortcutNumbers.count)
    }

    func testCatalogPresentationFieldsAreNonEmptyAndValid() {
        for definition in StoneCatalog.orderedDefinitions {
            XCTAssertFalse(definition.presentation.title.isEmpty)
            XCTAssertFalse(definition.presentation.placeholder.isEmpty)
            XCTAssertFalse(definition.presentation.systemImage.isEmpty)
            XCTAssertGreaterThan(definition.shortcutNumber, 0)
        }
    }

    func testFilesIsOnlyExistingStoneWithoutTextInput() {
        XCTAssertEqual(
            StoneCatalog.orderedDefinitions.filter { !$0.acceptsTextInput }.map(\.id),
            [.files]
        )
    }

    func testLookupReturnsNilForUnknownStoneIDRawValue() {
        XCTAssertNil(StoneID(rawValue: 99))
        XCTAssertNil(StoneCatalog.definition(forRawValue: 99))
    }

    func testCatalogPreservesCurrentUpdatePolicies() {
        XCTAssertEqual(StoneCatalog.definition(for: .applications).updatePolicy, .deferred(delayNanoseconds: 40_000_000))
        XCTAssertEqual(StoneCatalog.definition(for: .calculator).updatePolicy, .immediate)
        XCTAssertEqual(StoneCatalog.definition(for: .dictionary).updatePolicy, .deferred(delayNanoseconds: 80_000_000))
        XCTAssertEqual(StoneCatalog.definition(for: .files).updatePolicy, .immediate)
    }
}
