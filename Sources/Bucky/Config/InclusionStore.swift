import Foundation

final class InclusionStore {
    private let storage: JSONValueStore<InclusionsFile>
    var includedPaths: Set<String> { Set(storage.value.includedPaths) }
    var lastError: String? { storage.lastError?.localizedDescription }
    var fileURL: URL { storage.fileURL }

    init(fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("inclusions.json")) {
        storage = JSONValueStore(fileURL: fileURL, defaultValue: InclusionsFile(includedPaths: []),
                                createMissingFile: true)
    }
    @discardableResult func load() -> Bool { storage.load() }
    @MainActor @discardableResult func loadAsync() async -> Bool { await storage.loadAsync() }
    @discardableResult func add(path: String) -> Bool { add(paths: [path]) }
    @discardableResult func add(paths: [String]) -> Bool {
        storage.mutate { $0.includedPaths = Set($0.includedPaths).union(paths).sorted() }
    }
    @discardableResult func remove(path: String) -> Bool {
        storage.mutate { $0.includedPaths.removeAll { $0 == path } }
    }
    @MainActor @discardableResult func addAsync(paths: [String]) async -> Bool {
        await storage.mutateAsync { $0.includedPaths = Set($0.includedPaths).union(paths).sorted() }
    }
    @MainActor @discardableResult func removeAsync(path: String) async -> Bool {
        await storage.mutateAsync { $0.includedPaths.removeAll { $0 == path } }
    }
    func sortedPaths() -> [String] { includedPaths.sorted() }
}
