import Foundation

final class DictionaryHistoryStore {
    private let storage: JSONValueStore<DictionaryHistoryFile>
    var words: [DictionaryHistoryEntry] { storage.value.words }
    var lastError: String? { storage.lastError?.localizedDescription }
    var fileURL: URL { storage.fileURL }

    init(fileURL: URL? = nil) {
        storage = JSONValueStore(
            fileURL: fileURL ?? BuckyPaths.appSupportDirectory.appendingPathComponent("dictionary-history.json"),
            defaultValue: DictionaryHistoryFile(words: []))
    }
    @discardableResult func load() -> Bool { storage.load() }
    @MainActor @discardableResult func loadAsync() async -> Bool { await storage.loadAsync() }
    @discardableResult func add(term: String) -> Bool {
        guard !normalized(term.trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty else { return false }
        return storage.mutate { Self.add(term: term, to: &$0) }
    }
    @discardableResult func remove(term: String) -> Bool {
        let key = normalized(term.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { return false }
        return storage.mutate { $0.words.removeAll { normalized($0.term) == key } }
    }
    @MainActor @discardableResult func addAsync(term: String) async -> Bool {
        guard !normalized(term.trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty else { return false }
        return await storage.mutateAsync { Self.add(term: term, to: &$0) }
    }
    @MainActor @discardableResult func removeAsync(term: String) async -> Bool {
        let key = normalized(term.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { return false }
        return await storage.mutateAsync { $0.words.removeAll { normalized($0.term) == key } }
    }
    private static func add(term: String, to file: inout DictionaryHistoryFile) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        file.words.removeAll { normalized($0.term) == normalized(trimmed) }
        file.words.insert(DictionaryHistoryEntry(term: trimmed, date: Date()), at: 0)
        file.words = Array(file.words.prefix(100))
    }
}
