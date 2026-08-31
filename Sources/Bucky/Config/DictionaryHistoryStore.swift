import Foundation

final class DictionaryHistoryStore {
    private let fileManager = FileManager.default
    private(set) var words: [DictionaryHistoryEntry] = []
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? BuckyPaths.appSupportDirectory
            .appendingPathComponent("dictionary-history.json")
        load()
    }

    func load() {
        do {
            let file = try JSONFilePersistence.read(
                DictionaryHistoryFile.self,
                from: fileURL,
                decoder: JSONFilePersistence.makeDecoder()
            )
            words = file.words
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            words = []
        } catch {
            NSLog("Bucky could not read dictionary history at %@: %@", fileURL.path, error.localizedDescription)
            words = []
        }
    }

    func add(term: String) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTerm = normalized(trimmedTerm)
        guard !normalizedTerm.isEmpty else { return }

        words.removeAll { entry in
            normalized(entry.term) == normalizedTerm
        }
        words.insert(
            DictionaryHistoryEntry(term: trimmedTerm, date: Date()),
            at: 0
        )

        if words.count > 100 {
            words = Array(words.prefix(100))
        }

        save()
    }

    func remove(term: String) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTerm = normalized(trimmedTerm)
        guard !normalizedTerm.isEmpty else { return }

        words.removeAll { entry in
            normalized(entry.term) == normalizedTerm
        }
        save()
    }

    private func save() {
        do {
            try JSONFilePersistence.write(
                DictionaryHistoryFile(words: words),
                to: fileURL,
                fileManager: fileManager,
                encoder: JSONFilePersistence.makeEncoder()
            )
        } catch {
            NSLog("Bucky could not save dictionary history at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
