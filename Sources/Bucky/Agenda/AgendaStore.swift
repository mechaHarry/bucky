import Foundation

final class AgendaStore {
    private let fileManager: FileManager
    let fileURL: URL
    private(set) var notes: [AgendaNoteReference]

    init(
        fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("agenda.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        notes = []
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            notes = []
            return
        }

        do {
            let file = try JSONDecoder().decode(AgendaFile.self, from: data)
            notes = file.notes
        } catch {
            NSLog("Bucky could not read agenda at %@: %@", fileURL.path, error.localizedDescription)
            notes = []
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

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(AgendaFile(notes: notes))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save agenda at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
