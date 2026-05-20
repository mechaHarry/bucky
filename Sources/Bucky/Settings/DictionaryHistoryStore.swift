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
        guard let data = try? Data(contentsOf: fileURL) else {
            words = []
            return
        }

        do {
            let file = try JSONDecoder().decode(DictionaryHistoryFile.self, from: data)
            words = file.words
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
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let file = DictionaryHistoryFile(words: words)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save dictionary history at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
