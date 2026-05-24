import Foundation

final class AgendaStore {
    private let fileManager: FileManager
    let fileURL: URL
    private(set) var notes: [AgendaNoteReference]
    private(set) var reminders: [AgendaReminder]

    init(
        fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("agenda.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        notes = []
        reminders = []
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            notes = []
            reminders = []
            return
        }

        do {
            let file = try JSONDecoder().decode(AgendaFile.self, from: data)
            notes = file.notes
            reminders = file.reminders
        } catch {
            NSLog("Bucky could not read agenda at %@: %@", fileURL.path, error.localizedDescription)
            notes = []
            reminders = []
        }
    }

    @discardableResult
    func rememberNote(url: URL) -> AgendaNoteReference {
        let standardizedURL = url.standardizedFileURL
        if let existing = notes.first(where: { $0.url.standardizedFileURL == standardizedURL }) {
            return existing
        }

        let note = AgendaNoteReference(url: standardizedURL)
        notes.insert(note, at: 0)
        save()
        return note
    }

    func removeNote(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func createReminder(
        name: String = "New Reminder",
        date: String = "",
        time: String = "",
        urlString: String = "",
        details: String = ""
    ) -> AgendaReminder {
        let reminder = AgendaReminder(
            name: name,
            date: date,
            time: time,
            urlString: urlString,
            details: details
        )
        reminders.insert(reminder, at: 0)
        save()
        return reminder
    }

    func updateReminder(_ reminder: AgendaReminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
        save()
    }

    func removeReminder(id: UUID) {
        reminders.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(AgendaFile(notes: notes, reminders: reminders))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save agenda at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
