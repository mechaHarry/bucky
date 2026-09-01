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

    func testSharedResultsSurfaceIsNonTextAndUsesSafeModePresentation() {
        XCTAssertFalse(StoneSurface.sharedResults.acceptsTextInput)
        XCTAssertFalse(StoneSurface.sharedResults.usesFileBrowser)
        XCTAssertEqual(StoneSurface.sharedResults.activeModePresentation, .sharedResults)
        XCTAssertEqual(StoneSurface.fileBrowser.activeModePresentation, .fileBrowser)
    }

    @MainActor
    func testRegistryRejectsProvidersClaimingReservedFileBrowserSurface() {
        let registry = StoneProviderRegistry(providers: [
            ReservedFileBrowserProvider(),
            ReservedFileBrowserProvider(id: StoneID(rawValue: 99), shortcutNumber: 6)
        ])

        XCTAssertNil(registry.provider(for: .files))
        XCTAssertEqual(
            registry.availableModes.first(where: { $0.stoneID == .files })?.stoneDefinition,
            StoneCatalog.definition(for: .files)
        )
        XCTAssertFalse(registry.registeredStoneIDs.contains(.files))
        XCTAssertEqual(registry.availableModes.map(\.stoneID), StoneID.allCases)
    }

    func testAdditionalStoneIDDoesNotRequireStaticCatalogDefinition() {
        XCTAssertEqual(StoneID(rawValue: 99).rawValue, 99)
        XCTAssertNil(StoneCatalog.definition(forRawValue: 99))
    }

    func testCatalogPreservesCurrentUpdatePolicies() {
        XCTAssertEqual(StoneCatalog.definition(for: .applications).updatePolicy, .deferred(delayNanoseconds: 40_000_000))
        XCTAssertEqual(StoneCatalog.definition(for: .calculator).updatePolicy, .immediate)
        XCTAssertEqual(StoneCatalog.definition(for: .dictionary).updatePolicy, .deferred(delayNanoseconds: 80_000_000))
        XCTAssertEqual(StoneCatalog.definition(for: .files).updatePolicy, .immediate)
    }

    func testLauncherModeEqualityUsesStoneIdentity() {
        let replacementDefinition = StoneDefinition(
            id: .calculator,
            shortcutNumber: 20,
            presentation: StonePresentation(
                title: "Replacement",
                placeholder: "Enter Text Here",
                systemImage: "text.cursor"
            ),
            surface: .textInput,
            updatePolicy: .immediate,
            tint: StoneTint(
                activeHex: 0x102030,
                panelHex: 0x203040,
                iconHex: 0x304050,
                darkModeIconHex: 0xC0D0E0
            )
        )

        XCTAssertEqual(LauncherMode(definition: replacementDefinition), .calculator)
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

@MainActor
private final class ReservedFileBrowserProvider: StoneProvider {
    let definition: StoneDefinition

    init(id: StoneID = .files, shortcutNumber: Int = 4) {
        definition = StoneDefinition(
            id: id,
            shortcutNumber: shortcutNumber,
            presentation: StonePresentation(
                title: "Replacement Files",
                placeholder: "Not allowed",
                systemImage: "exclamationmark.triangle"
            ),
            surface: .fileBrowser,
            updatePolicy: .immediate,
            tint: StoneCatalog.definition(for: .files).tint
        )
    }

    func snapshot(for query: String) -> StoneResultSnapshot { .loaded(rows: []) }
    func updateSnapshot(for query: String) async -> StoneResultSnapshot { snapshot(for: query) }
    func cancel() {}
    func activation(for row: StoneResultRow) -> StoneActivation { .none }
    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> StoneProviderActivationResult { .unhandled }
}
