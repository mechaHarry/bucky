import XCTest
@testable import Bucky

final class CountdownStoneTests: XCTestCase {
    func testRemainingBreaksFutureIntervalIntoDaysHoursMinutesSecondsAndMilliseconds() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let target = now.addingTimeInterval((2 * 86_400) + (3 * 3_600) + (4 * 60) + 5.678)

        XCTAssertEqual(
            CountdownRemaining(until: target, now: now),
            CountdownRemaining(days: 2, hours: 3, minutes: 4, seconds: 5, milliseconds: 678)
        )
    }

    func testRemainingClampsPastTargetToZero() {
        let now = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertEqual(
            CountdownRemaining(until: now.addingTimeInterval(-0.001), now: now),
            CountdownRemaining.zero
        )
    }

    func testRemainingBoundsExtremeFutureDatesWithoutOverflowing() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let remaining = CountdownRemaining(
            until: Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude),
            now: now
        )

        XCTAssertGreaterThan(remaining.days, 0)
        XCTAssertGreaterThanOrEqual(remaining.milliseconds, 0)
    }

    func testRemainingFormatsEveryUnitWithStablePadding() {
        let remaining = CountdownRemaining(days: 2, hours: 3, minutes: 4, seconds: 5, milliseconds: 6)

        XCTAssertEqual(remaining.displayString, "2d 03h 04m 05s 006ms")
    }

    func testCountdownStorePersistsAndUpdatesNamedCountdowns() throws {
        let fileURL = temporaryFileURL()
        let store = CountdownStore(fileURL: fileURL)
        let target = Date(timeIntervalSinceReferenceDate: 1234)

        let countdown = try XCTUnwrap(store.add(name: "Release", targetDate: target))
        XCTAssertEqual(store.countdowns, [countdown])

        XCTAssertTrue(store.update(id: countdown.id, name: "Launch", targetDate: target.addingTimeInterval(60)))
        XCTAssertEqual(store.countdowns.first?.name, "Launch")

        let reloaded = CountdownStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.countdowns, store.countdowns)
    }

    func testCountdownStoreRejectsBlankNamesAndRemovesByStableID() throws {
        let store = CountdownStore(fileURL: temporaryFileURL())
        XCTAssertNil(store.add(name: "  ", targetDate: Date()))

        let first = try XCTUnwrap(store.add(name: "First", targetDate: Date()))
        let second = try XCTUnwrap(store.add(name: "Second", targetDate: Date()))
        XCTAssertTrue(store.remove(id: first.id))
        XCTAssertFalse(store.remove(id: first.id))
        XCTAssertEqual(store.countdowns, [second])
    }

    func testCountdownStoreNormalizesAndCapsPersistedNames() throws {
        let store = CountdownStore(fileURL: temporaryFileURL())
        let longName = String(repeating: "x", count: 250)

        let countdown = try XCTUnwrap(store.add(name: "  Project   launch  ", targetDate: Date()))
        XCTAssertEqual(countdown.name, "Project launch")

        let capped = try XCTUnwrap(store.add(name: longName, targetDate: Date()))
        XCTAssertEqual(capped.name.count, 200)

        for index in 0..<105 {
            _ = store.add(name: "Countdown \(index)", targetDate: Date())
        }
        XCTAssertEqual(store.countdowns.count, 100)

        let before = store.countdowns
        XCTAssertNil(store.add(name: "Overflow", targetDate: Date()))
        XCTAssertEqual(store.countdowns, before)
        XCTAssertTrue(store.countdowns.contains { $0.id == countdown.id })
        XCTAssertEqual(store.countdowns.count, 100)
        XCTAssertNotNil(store.lastError)
    }

    func testMalformedCountdownFileFallsBackToEmptyStore() throws {
        let fileURL = temporaryFileURL()
        try Data("not json".utf8).write(to: fileURL)

        let store = CountdownStore(fileURL: fileURL)

        XCTAssertEqual(store.countdowns, [])
    }

    func testPersistedCountdownsAreSanitizedBeforeDisplay() throws {
        let fileURL = temporaryFileURL()
        let duplicateID = UUID()
        let file = CountdownsFile(countdowns: [
            Countdown(id: duplicateID, name: "  First   target ", targetDate: Date()),
            Countdown(id: duplicateID, name: "Second target", targetDate: Date()),
            Countdown(name: "   ", targetDate: Date())
        ])
        let data = try JSONEncoder().encode(file)
        try data.write(to: fileURL)

        let store = CountdownStore(fileURL: fileURL)

        XCTAssertEqual(store.countdowns.count, 1)
        XCTAssertEqual(store.countdowns.first?.name, "First target")
        XCTAssertNotNil(store.lastError)
        XCTAssertNil(store.add(name: "Another target", targetDate: Date().addingTimeInterval(60)))
        XCTAssertEqual(try Data(contentsOf: fileURL), data)
    }

    @MainActor
    func testCountdownStoneDefinitionUsesSharedResultsGreenTintAndLiveRefresh() {
        let stone = CountdownStone(store: CountdownStore(fileURL: temporaryFileURL()))

        XCTAssertEqual(stone.definition.id, .countdowns)
        XCTAssertEqual(stone.definition.shortcutNumber, 5)
        XCTAssertEqual(stone.definition.presentation.title, "Countdowns")
        XCTAssertEqual(stone.definition.surface, .sharedResults)
        XCTAssertEqual(stone.definition.tint.activeHex, 0x34C759)
        XCTAssertNil(stone.definition.refreshIntervalNanoseconds, "Visible rows own the clock, not the launcher model")
        XCTAssertFalse(stone.definition.animatesResultUpdates)
    }

    @MainActor
    func testCountdownStoneProvidesInlineCreationConfiguration() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let stone = CountdownStone(
            store: CountdownStore(fileURL: temporaryFileURL()),
            now: { now }
        )

        XCTAssertEqual(stone.inlineCreationConfiguration.namePlaceholder, "Countdown name")
        XCTAssertEqual(stone.inlineCreationConfiguration.targetDateLabel, "Target date and time")
        XCTAssertEqual(stone.inlineCreationConfiguration.systemImage, "timer")
        XCTAssertEqual(stone.inlineCreationConfiguration.defaultTargetDate, now.addingTimeInterval(3_600))
    }

    @MainActor
    func testCountdownStoneSubmitsInlineCreationWithoutModalState() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let store = CountdownStore(fileURL: temporaryFileURL())
        let stone = CountdownStone(store: store, now: { now })

        XCTAssertFalse(stone.submitInlineCreation(name: " ", targetDate: now.addingTimeInterval(60)))
        XCTAssertFalse(stone.submitInlineCreation(name: "Release", targetDate: now))
        XCTAssertTrue(stone.submitInlineCreation(name: "  Release   day  ", targetDate: now.addingTimeInterval(60)))
        XCTAssertEqual(store.countdowns.map(\.name), ["Release day"])
    }

    @MainActor
    func testCountdownRowsExposeDeleteActionWithoutEditModal() throws {
        let store = CountdownStore(fileURL: temporaryFileURL())
        let countdown = try XCTUnwrap(store.add(name: "Release", targetDate: Date()))
        let row = try XCTUnwrap(CountdownStone.rows(for: [countdown], now: Date()).last)

        XCTAssertEqual(row.primaryActivation, .none)
        XCTAssertEqual(row.accessoryActivation, .providerAction("delete:\(countdown.id.uuidString)"))
        XCTAssertEqual(row.accessoryPresentation, .init(systemImage: "trash", help: "Delete countdown"))
        XCTAssertEqual(row.iconSystemImage, "timer")
    }

    @MainActor
    func testCountdownDeleteUsesSharedConfirmationThenDeletesOnConfirmation() throws {
        let store = CountdownStore(fileURL: temporaryFileURL())
        let countdown = try XCTUnwrap(store.add(name: "Release", targetDate: Date()))
        let row = try XCTUnwrap(CountdownStone.rows(for: [countdown], now: Date()).last)
        let stone = CountdownStone(store: store)

        guard case let .confirmation(confirmation) = stone.perform(row.accessoryActivation, for: row) else {
            return XCTFail("Expected shared confirmation")
        }

        XCTAssertEqual(confirmation.title, "Delete countdown?")
        XCTAssertEqual(confirmation.confirmationActivation, .providerAction("delete-confirm:\(countdown.id.uuidString)"))
        XCTAssertEqual(
            stone.perform(confirmation.confirmationActivation, for: row),
            .handled(shouldRefresh: true, resetSelection: true, shouldHide: false)
        )
        XCTAssertTrue(store.countdowns.isEmpty)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCountdownClockDoesNotRebuildTheLauncherSnapshot() async throws {
        let clock = MutableCountdownClock(date: Date(timeIntervalSinceReferenceDate: 100))
        let store = CountdownStore(fileURL: temporaryFileURL())
        _ = try XCTUnwrap(store.add(name: "Release", targetDate: clock.date.addingTimeInterval(0.2)))
        let stone = CountdownStone(store: store, now: { clock.date })
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            stoneProviders: [stone],
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )
        let mode = try XCTUnwrap(model.availableModes.first { $0.stoneID == .countdowns })

        model.show(mode: mode)
        XCTAssertEqual(model.resultSnapshot.rows[0].subtitle, "0d 00h 00m 00s 200ms")

        let initial = model.resultSnapshot
        XCTAssertEqual(initial.rows[0].countdownTarget, clock.date.addingTimeInterval(0.2))
        clock.date = clock.date.addingTimeInterval(0.2)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(model.resultSnapshot, initial)
        XCTAssertEqual(CountdownRemaining(until: try XCTUnwrap(initial.rows[0].countdownTarget), now: clock.date), .zero)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testLauncherSubmitsInlineCreationAndRefreshesTheSharedResultList() throws {
        let clock = MutableCountdownClock(date: Date(timeIntervalSinceReferenceDate: 100))
        let stone = CountdownStone(store: CountdownStore(fileURL: temporaryFileURL()), now: { clock.date })
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            stoneProviders: [stone],
            fileBrowserModel: FileBrowserModel(
                fileSystem: StubFileSystemClient(home: TestFixtures.userHome, entriesByDirectory: [:]),
                store: InMemoryFileBrowserStore(state: .defaultValue),
                directoryStream: ImmediateDirectoryStream()
            )
        )
        let mode = try XCTUnwrap(model.availableModes.first { $0.stoneID == .countdowns })

        model.show(mode: mode)

        XCTAssertTrue(model.submitInlineCreation(name: "Launch", targetDate: clock.date.addingTimeInterval(60)))
        XCTAssertEqual(model.resultSnapshot.rows.map(\.display), ["Launch"])
    }

    @MainActor
    func testCountdownStonePublishesCountdownRowsBelowInlineCreationSurface() throws {
        let store = CountdownStore(fileURL: temporaryFileURL())
        let countdown = try XCTUnwrap(store.add(
            name: "Release",
            targetDate: Date(timeIntervalSinceReferenceDate: 1234)
        ))
        let stone = CountdownStone(store: store, now: { Date(timeIntervalSinceReferenceDate: 100) })

        let rows = stone.snapshot(for: "").rows

        XCTAssertEqual(rows.map(\.display), ["Release"])
        XCTAssertEqual(rows[0].subtitle, "0d 00h 18m 54s 000ms")
        XCTAssertEqual(rows[0].id, .tool(kind: .message, key: "countdown:\(countdown.id.uuidString)"))
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyCountdownStone-\(UUID().uuidString).json")
    }

    @MainActor
    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

@MainActor
private final class MutableCountdownClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
