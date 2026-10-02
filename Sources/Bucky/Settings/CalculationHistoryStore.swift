import Foundation

final class CalculationHistoryStore {
    private let storage: JSONValueStore<CalculationHistoryFile>
    var calculations: [CalculationHistoryEntry] { storage.value.calculations }
    var lastError: String? { storage.lastError?.localizedDescription }
    var fileURL: URL { storage.fileURL }

    init(fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("calculations.json")) {
        storage = JSONValueStore(fileURL: fileURL, defaultValue: CalculationHistoryFile(calculations: []))
    }
    @discardableResult func load() -> Bool { storage.load() }
    @MainActor @discardableResult func loadAsync() async -> Bool { await storage.loadAsync() }
    @discardableResult func add(expression: String, result: String) -> Bool {
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return storage.mutate { Self.add(expression: expression, result: result, to: &$0) }
    }
    @discardableResult func clear() -> Bool {
        storage.mutate { $0.calculations = [] }
    }
    @MainActor @discardableResult
    func addAsync(expression: String, result: String) async -> Bool {
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return await storage.mutateAsync { Self.add(expression: expression, result: result, to: &$0) }
    }
    @MainActor @discardableResult
    func clearAsync() async -> Bool {
        await storage.mutateAsync { $0.calculations = [] }
    }
    private static func add(expression: String, result: String, to file: inout CalculationHistoryFile) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        file.calculations.removeAll { $0.expression == trimmed && $0.result == result }
        file.calculations.insert(CalculationHistoryEntry(expression: trimmed, result: result, date: Date()), at: 0)
        file.calculations = Array(file.calculations.prefix(100))
    }
}
