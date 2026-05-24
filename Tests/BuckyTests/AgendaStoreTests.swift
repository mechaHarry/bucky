import XCTest
@testable import Bucky

final class AgendaStoreTests: XCTestCase {
    func testNotesAndRemindersRoundTripThroughStore() throws {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Plan.md")

        let note = store.rememberNote(url: noteURL)
        let reminder = store.createReminder(
            name: "Ship Agenda",
            date: "2026-05-24",
            time: "09:30",
            urlString: "bucky://agenda",
            details: "Finish the first slice"
        )

        let reloaded = AgendaStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.notes, [note])
        XCTAssertEqual(reloaded.reminders, [reminder])
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

    func testRemovingReminderDeletesReminderRecord() throws {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let reminder = store.createReminder(name: "Delete me")

        store.removeReminder(id: reminder.id)

        XCTAssertTrue(store.reminders.isEmpty)
        XCTAssertTrue(AgendaStore(fileURL: fileURL).reminders.isEmpty)
    }

    func testFilterMatchesNoteAndReminderMetadata() throws {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        _ = store.rememberNote(url: URL(fileURLWithPath: "/tmp/ReleaseNotes.mdx"))
        _ = store.createReminder(
            name: "Renew cert",
            date: "2026-06-01",
            time: "14:00",
            urlString: "bucky://security",
            details: "Check expiry"
        )

        let notes = AgendaFilter.filterNotes(store.notes, query: "release mdx")
        let reminders = AgendaFilter.filterReminders(store.reminders, query: "security expiry")

        XCTAssertEqual(notes.map(\.title), ["ReleaseNotes.mdx"])
        XCTAssertEqual(reminders.map(\.name), ["Renew cert"])
    }

    func testMalformedStoreFallsBackToEmptyAgenda() throws {
        let fileURL = temporaryStoreURL()
        try "{ bad json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = AgendaStore(fileURL: fileURL)

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(store.reminders.isEmpty)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testLauncherAgendaFiltersBothColumnsAndRemovesSelectedKind() {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let noteURL = fileURL.deletingLastPathComponent().appendingPathComponent("Design.md")
        try? "Agenda".write(to: noteURL, atomically: true, encoding: .utf8)
        let note = store.rememberNote(url: noteURL)
        let reminder = store.createReminder(name: "Design review")
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
        XCTAssertEqual(model.filteredAgendaReminders.map(\.id), [reminder.id])

        model.agendaSelectionColumn = .notes
        XCTAssertTrue(model.handle(command: .removeAgendaSelection))
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.url.path))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(store.reminders.map(\.id), [reminder.id])

        model.agendaSelectionColumn = .reminders
        XCTAssertTrue(model.handle(command: .removeAgendaSelection))
        XCTAssertTrue(store.reminders.isEmpty)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testOpeningNoteUsesExplicitSaveAndEscapeClosesEditor() throws {
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
        model.agendaSelectionColumn = .notes
        XCTAssertTrue(model.handle(command: .open))
        XCTAssertEqual(model.openedAgendaNote?.id, note.id)
        XCTAssertEqual(model.agendaOpenNoteText, "original")

        model.agendaOpenNoteText = "draft text"
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "original")

        XCTAssertTrue(model.handle(command: .saveAgendaNote))
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "draft text")

        XCTAssertTrue(model.handle(command: .close))
        XCTAssertNil(model.openedAgendaNote)
    }

    private func temporaryStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyAgendaStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("agenda.json")
    }
}
