import XCTest
@testable import Bucky

final class AgendaStoreTests: XCTestCase {
    func testNotesRoundTripThroughStore() throws {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Plan.md")

        let note = store.rememberNote(url: noteURL)

        let reloaded = AgendaStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.notes, [note])
    }

    func testRemovingNoteOnlyForgetsReferenceAndKeepsFileOnDisk() throws {
        let fileURL = temporaryStoreURL()
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Keep.md")
        try "# Keep".write(to: noteURL, atomically: true, encoding: .utf8)
        let store = AgendaStore(fileURL: fileURL)
        let note = store.rememberNote(url: noteURL)

        store.removeNote(id: note.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testFilterMatchesNoteMetadata() throws {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        _ = store.rememberNote(url: URL(fileURLWithPath: "/tmp/ReleaseNotes.mdx"))

        let notes = AgendaFilter.filterNotes(store.notes, query: "release mdx")

        XCTAssertEqual(notes.map(\.title), ["ReleaseNotes.mdx"])
    }

    func testMalformedStoreFallsBackToEmptyAgenda() throws {
        let fileURL = temporaryStoreURL()
        try "{ bad json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = AgendaStore(fileURL: fileURL)

        XCTAssertTrue(store.notes.isEmpty)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testLauncherAgendaFiltersNotesAndRemovesSelectedNoteReference() {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Design.md")
        try? "Agenda".write(to: noteURL, atomically: true, encoding: .utf8)
        let note = store.rememberNote(url: noteURL)
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            agendaStore: store
        )

        model.show(mode: .agenda)
        model.insertTextInput("d")
        model.insertTextInput("e")
        model.insertTextInput("s")

        XCTAssertEqual(model.filteredAgendaNotes.map(\.id), [note.id])

        XCTAssertTrue(model.handle(command: .removeAgendaSelection))
        XCTAssertTrue(model.isConfirmingAgendaRemoval)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.url.path))
        XCTAssertEqual(store.notes.map(\.id), [note.id])
        model.confirmAgendaRemoval()
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.url.path))
        XCTAssertTrue(store.notes.isEmpty)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCancellingAgendaRemovalKeepsSelectedNote() throws {
        let fileURL = temporaryStoreURL()
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Keep.md")
        try "keep".write(to: noteURL, atomically: true, encoding: .utf8)
        let store = AgendaStore(fileURL: fileURL)
        let note = store.rememberNote(url: noteURL)
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            agendaStore: store
        )

        model.show(mode: .agenda)
        XCTAssertTrue(model.handle(command: .removeAgendaSelection))
        XCTAssertTrue(model.isConfirmingAgendaRemoval)

        XCTAssertTrue(model.handle(command: .close))

        XCTAssertFalse(model.isConfirmingAgendaRemoval)
        XCTAssertEqual(store.notes.map(\.id), [note.id])
    }

    @MainActor
    @available(macOS 26.0, *)
    func testClosingOpenedNoteSavesDraftAndClosesEditor() throws {
        let fileURL = temporaryStoreURL()
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Draft.md")
        try "original".write(to: noteURL, atomically: true, encoding: .utf8)
        let store = AgendaStore(fileURL: fileURL)
        let note = store.rememberNote(url: noteURL)
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            agendaStore: store
        )

        model.show(mode: .agenda)
        XCTAssertTrue(model.handle(command: .open))
        XCTAssertEqual(model.openedAgendaNote?.id, note.id)
        XCTAssertEqual(model.agendaOpenNoteText, "original")

        model.agendaOpenNoteText = "draft text"
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "original")

        XCTAssertTrue(model.handle(command: .close))

        XCTAssertNil(model.openedAgendaNote)
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "draft text")
    }

    @MainActor
    @available(macOS 26.0, *)
    func testClosingAgendaSearchDoesNotCloseOpenedNote() throws {
        let fileURL = temporaryStoreURL()
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Search.md")
        try "alpha beta".write(to: noteURL, atomically: true, encoding: .utf8)
        let store = AgendaStore(fileURL: fileURL)
        let note = store.rememberNote(url: noteURL)
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            agendaStore: store
        )

        model.show(mode: .agenda)
        XCTAssertTrue(model.handle(command: .open))
        model.isAgendaNoteSearchVisible = true

        XCTAssertTrue(model.handle(command: .close))

        XCTAssertFalse(model.isAgendaNoteSearchVisible)
        XCTAssertEqual(model.openedAgendaNote?.id, note.id)
    }

    private func temporaryStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyAgendaStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("agenda.json")
    }
}
