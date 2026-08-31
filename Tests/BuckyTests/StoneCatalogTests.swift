import XCTest
@testable import Bucky

final class StoneCatalogTests: XCTestCase {
    @MainActor
    func testRegisteredTextStoneProviderSuppliesSnapshotsAndActivations() async {
        let provider = TestTextStoneProvider()
        let registry = StoneProviderRegistry(providers: [provider])
        let row = StoneResultRow(
            id: .tool(kind: .message, key: "registry-row"),
            display: "Registry result",
            subtitle: "Provided by test stone",
            copyText: nil,
            kind: .message,
            primaryActivation: .none,
            accessoryActivation: .none
        )

        XCTAssertEqual(
            registry.snapshot(for: .calculator, query: "input"),
            .loading(message: "Preparing result")
        )
        let updatedSnapshot = await registry.updateSnapshot(for: .calculator, query: "input")
        XCTAssertEqual(updatedSnapshot, .loaded(rows: [row]))
        XCTAssertEqual(
            registry.activation(for: .calculator, row: row),
            .copy("Registry result")
        )
    }

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

@MainActor
private final class TestTextStoneProvider: TextStoneProvider {
    let definition = StoneCatalog.definition(for: .calculator)

    func snapshot(for query: String) -> StoneResultSnapshot {
        .loading(message: "Preparing result")
    }

    func updateSnapshot(for query: String) async -> StoneResultSnapshot {
        .loaded(rows: [StoneResultRow(
            id: .tool(kind: .message, key: "registry-row"),
            display: "Registry result",
            subtitle: "Provided by test stone",
            copyText: nil,
            kind: .message,
            primaryActivation: .none,
            accessoryActivation: .none
        )])
    }

    func cancel() {}

    func activation(for row: StoneResultRow) -> StoneActivation {
        .copy(row.display)
    }

    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> TextStoneActivationResult {
        .unhandled
    }
}
