import AppKit
import Carbon
import XCTest
@testable import Bucky

@available(macOS 26.0, *)
@MainActor
final class AuditHardeningTests: XCTestCase {
    func testFailedCountdownWriteDoesNotPublishNewRecords() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("countdowns.json")
        let store = CountdownStore(fileURL: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        XCTAssertNil(store.add(name: "Target", targetDate: Date().addingTimeInterval(60)))
        XCTAssertTrue(store.countdowns.isEmpty)
        XCTAssertNotNil(store.lastError)
    }

    func testMalformedCountdownReloadPreservesLastValidStateAndFile() throws {
        let fileURL = try temporaryDirectory().appendingPathComponent("countdowns.json")
        let store = CountdownStore(fileURL: fileURL)
        let countdown = try XCTUnwrap(store.add(name: "Target", targetDate: Date().addingTimeInterval(60)))
        let malformed = Data("incomplete JSON".utf8)
        try malformed.write(to: fileURL)
        store.load()
        XCTAssertEqual(store.countdowns, [countdown])
        XCTAssertNil(store.add(name: "Another", targetDate: Date().addingTimeInterval(120)))
        XCTAssertEqual(try Data(contentsOf: fileURL), malformed)
    }

    func testExistingCountdownsBeyondCreationCapacityAreNotTruncatedOrRewritten() throws {
        let fileURL = try temporaryDirectory().appendingPathComponent("countdowns.json")
        let records = (0...CountdownStore.maximumCountdowns).map {
            Countdown(name: "Target \($0)", targetDate: Date().addingTimeInterval(60))
        }
        let data = try JSONEncoder().encode(CountdownsFile(countdowns: records))
        try data.write(to: fileURL)
        let store = CountdownStore(fileURL: fileURL)
        XCTAssertEqual(store.countdowns, records)
        XCTAssertNil(store.add(name: "Overflow", targetDate: Date().addingTimeInterval(120)))
        XCTAssertEqual(try Data(contentsOf: fileURL), data)
    }

    func testConfirmationOwnsItsStoneAndBlocksBackgroundCommands() throws {
        let store = CountdownStore(fileURL: try temporaryDirectory().appendingPathComponent("countdowns.json"))
        _ = try XCTUnwrap(store.add(name: "Target", targetDate: Date().addingTimeInterval(60)))
        let model = makeModel(stone: CountdownStone(store: store))
        let countdownMode = try XCTUnwrap(model.mode(forCommandNumber: 5))
        model.show(mode: countdownMode)
        model.performAccessoryActivation(for: try XCTUnwrap(model.resultSnapshot.rows.first))
        XCTAssertNotNil(model.providerConfirmation)
        XCTAssertTrue(model.handle(command: .switchMode(.applications)))
        XCTAssertEqual(model.mode, countdownMode)
        XCTAssertTrue(model.handle(command: .close))
        XCTAssertNil(model.providerConfirmation)
        XCTAssertTrue(model.handle(command: .switchMode(.applications)))
        XCTAssertEqual(model.mode, .applications)
        XCTAssertEqual(store.countdowns.count, 1)
    }

    func testConfirmedCountdownDeletePersistsBeforePublishing() async throws {
        let fileURL = try temporaryDirectory().appendingPathComponent("countdowns.json")
        let store = CountdownStore(fileURL: fileURL)
        _ = try XCTUnwrap(store.add(name: "Target", targetDate: Date().addingTimeInterval(60)))
        let model = makeModel(stone: CountdownStone(store: store))
        model.show(mode: try XCTUnwrap(model.mode(forCommandNumber: 5)))
        model.performAccessoryActivation(for: try XCTUnwrap(model.resultSnapshot.rows.first))
        model.confirmProviderConfirmation()
        for _ in 0..<100 where !store.countdowns.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(store.countdowns.isEmpty)
        XCTAssertTrue(CountdownStore(fileURL: fileURL).countdowns.isEmpty)
        XCTAssertTrue(model.resultSnapshot.rows.isEmpty)
    }

    func testCalculatorProviderUsesSharedRowsAndHistoryContract() throws {
        let store = CalculationHistoryStore(fileURL: try temporaryDirectory().appendingPathComponent("calculations.json"))
        let provider = CalculatorStone(store: store)
        let result = provider.snapshot(for: "2 + 2", recordingHistory: false)
        XCTAssertEqual(result.rows.first?.display, "4")
        XCTAssertEqual(result.rows.first?.primaryActivation, .copy("4"))
        XCTAssertFalse(provider.canClearHistory)
        XCTAssertTrue(store.add(expression: "3 + 3", result: "6"))
        XCTAssertTrue(provider.canClearHistory)
        XCTAssertEqual(provider.snapshot(for: "", recordingHistory: false).rows.first?.kind, .calculationHistory)
    }

    func testCalculatorCallbackDoesNotRetainTheLauncherModel() {
        weak var weakModel: LiquidGlassLauncherModel?
        do {
            let model = makeModel()
            weakModel = model
        }
        XCTAssertNil(weakModel)
    }

    func testRejectedProviderCannotDisableTheBuiltInCalculator() {
        let model = makeModel(stone: RejectedCalculatorProvider())
        model.show(mode: .calculator)
        model.query = "2 + 2"
        model.queryDidChange()
        XCTAssertEqual(model.resultSnapshot.rows.first?.display, "4")
    }

    func testSharedShortcutDecoderUsesRegisteredModesAndLeavesClipboardKeysNative() throws {
        let model = makeModel(stone: CountdownStone(store: CountdownStore(fileURL: try temporaryDirectory().appendingPathComponent("countdowns.json"))))
        let event = try keyEvent("5", keyCode: UInt16(kVK_ANSI_5))
        XCTAssertEqual(LauncherShortcutPolicy.command(for: event, modeForNumber: model.mode(forCommandNumber:)),
                       .switchMode(try XCTUnwrap(model.mode(forCommandNumber: 5))))
        for key in ["a", "c", "v", "x"] {
            XCTAssertNil(LauncherShortcutPolicy.command(for: try keyEvent(key), modeForNumber: model.mode(forCommandNumber:)))
        }
    }

    private func makeModel(stone: (any StoneProvider)? = nil) -> LiquidGlassLauncherModel {
        LiquidGlassLauncherModel(settingsStore: SettingsStore(), inclusionStore: InclusionStore(),
                                exclusionStore: ExclusionStore(), calculationHistoryStore: CalculationHistoryStore(),
                                stoneProviders: stone.map { [$0] } ?? [])
    }

    private func keyEvent(_ key: String, keyCode: UInt16 = 0) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                      timestamp: 0, windowNumber: 0, context: nil, characters: key,
                                      charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bucky-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

@MainActor
private final class RejectedCalculatorProvider: StoneProvider {
    var definition: StoneDefinition {
        let original = StoneCatalog.definition(for: .calculator)
        return StoneDefinition(id: original.id, shortcutNumber: original.shortcutNumber,
                               presentation: original.presentation, surface: .fileBrowser,
                               updatePolicy: original.updatePolicy, tint: original.tint)
    }
    func snapshot(for query: String) -> StoneResultSnapshot { .empty(message: "Rejected provider") }
    func updateSnapshot(for query: String) async -> StoneResultSnapshot { snapshot(for: query) }
    func cancel() {}
    func activation(for row: StoneResultRow) -> StoneActivation { .none }
    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> StoneProviderActivationResult { .unhandled }
}
