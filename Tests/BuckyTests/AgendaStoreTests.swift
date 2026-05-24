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

    func testReminderMetadataExposesEveryVisibleListField() {
        let reminder = AgendaReminder(
            name: "Renew cert",
            date: "2026-06-01",
            time: "14:00",
            urlString: "bucky://security",
            details: "Check expiry"
        )

        XCTAssertEqual(reminder.metadataLines, [
            "2026-06-01 14:00",
            "bucky://security",
            "Check expiry"
        ])
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
    func testReturnConfirmsAgendaRemovalOverlay() {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let reminder = store.createReminder(name: "Delete me")
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            agendaStore: store
        )

        model.show(mode: .agenda)
        model.agendaSelectionColumn = .reminders
        XCTAssertTrue(model.handle(command: .removeAgendaSelection))

        XCTAssertTrue(model.handle(command: .open))

        XCTAssertFalse(model.isConfirmingAgendaRemoval)
        XCTAssertFalse(store.reminders.contains { $0.id == reminder.id })
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
        XCTAssertTrue(model.isConfirmingAgendaRemoval)
        XCTAssertEqual(model.pendingAgendaRemovalColumn, .notes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.url.path))
        XCTAssertEqual(store.notes.map(\.id), [note.id])
        model.confirmAgendaRemoval()
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.url.path))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(store.reminders.map(\.id), [reminder.id])

        model.agendaSelectionColumn = .reminders
        XCTAssertTrue(model.handle(command: .removeAgendaSelection))
        XCTAssertTrue(model.isConfirmingAgendaRemoval)
        XCTAssertEqual(model.pendingAgendaRemovalColumn, .reminders)
        XCTAssertEqual(store.reminders.map(\.id), [reminder.id])
        model.confirmAgendaRemoval()
        XCTAssertTrue(store.reminders.isEmpty)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testCancellingAgendaRemovalKeepsSelectedRow() throws {
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
        model.agendaSelectionColumn = .notes
        XCTAssertTrue(model.handle(command: .removeAgendaSelection))
        XCTAssertTrue(model.isConfirmingAgendaRemoval)

        XCTAssertTrue(model.handle(command: .close))

        XCTAssertFalse(model.isConfirmingAgendaRemoval)
        XCTAssertEqual(store.notes.map(\.id), [note.id])
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

    @MainActor
    @available(macOS 26.0, *)
    func testCreatingReminderUsesDraftOverlayBeforePersisting() {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let scheduler = RecordingAgendaReminderScheduler()
        let model = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            agendaStore: store,
            agendaReminderScheduler: scheduler
        )

        model.show(mode: .agenda)
        model.agendaSelectionColumn = .reminders
        XCTAssertTrue(model.handle(command: .createAgendaItem))

        XCTAssertTrue(model.isCreatingAgendaReminder)
        XCTAssertTrue(store.reminders.isEmpty)

        model.draftAgendaReminder.name = "Design review"
        model.draftAgendaReminder.date = "2026-05-24"
        model.draftAgendaReminder.time = "09:30"
        model.draftAgendaReminder.urlString = "bucky://agenda"
        model.draftAgendaReminder.details = "Review the reminder overlay"
        model.createDraftAgendaReminder()

        XCTAssertFalse(model.isCreatingAgendaReminder)
        XCTAssertEqual(store.reminders.map(\.name), ["Design review"])
        XCTAssertEqual(store.reminders.first?.date, "2026-05-24")
        XCTAssertEqual(store.reminders.first?.time, "09:30")
        XCTAssertEqual(store.reminders.first?.urlString, "bucky://agenda")
        XCTAssertEqual(scheduler.scheduledReminderIDs, store.reminders.map(\.id))
        XCTAssertEqual(scheduler.scheduledReminders.first?.notificationDateComponents?.year, 2026)
        XCTAssertEqual(scheduler.scheduledReminders.first?.notificationDateComponents?.month, 5)
        XCTAssertEqual(scheduler.scheduledReminders.first?.notificationDateComponents?.day, 24)
        XCTAssertEqual(scheduler.scheduledReminders.first?.notificationDateComponents?.hour, 9)
        XCTAssertEqual(scheduler.scheduledReminders.first?.notificationDateComponents?.minute, 30)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testExistingRemindersSyncToNotificationSchedulerOnLaunch() {
        let fileURL = temporaryStoreURL()
        let store = AgendaStore(fileURL: fileURL)
        let reminder = store.createReminder(name: "Standup", date: "2026-05-24", time: "10:00")
        let scheduler = RecordingAgendaReminderScheduler()

        _ = LiquidGlassLauncherModel(
            settingsStore: SettingsStore(),
            inclusionStore: InclusionStore(),
            exclusionStore: ExclusionStore(),
            calculationHistoryStore: CalculationHistoryStore(),
            agendaStore: store,
            agendaReminderScheduler: scheduler
        )

        XCTAssertEqual(scheduler.syncedReminders.map(\.id), [reminder.id])
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
        model.agendaSelectionColumn = .notes
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

private final class RecordingAgendaReminderScheduler: AgendaReminderScheduling {
    private(set) var syncedReminders: [AgendaReminder] = []
    private(set) var scheduledReminders: [AgendaReminder] = []
    private(set) var canceledReminderIDs: [UUID] = []

    var scheduledReminderIDs: [UUID] {
        scheduledReminders.map(\.id)
    }

    func sync(reminders: [AgendaReminder]) {
        syncedReminders = reminders
    }

    func schedule(_ reminder: AgendaReminder) {
        scheduledReminders.append(reminder)
    }

    func cancelReminder(id: UUID) {
        canceledReminderIDs.append(id)
    }
}
