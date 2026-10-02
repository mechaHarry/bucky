import Foundation

final class ExclusionStore {
    private let storage: JSONValueStore<ExclusionsFile>
    var excludedPaths: Set<String> { Set(storage.value.excludedPaths) }
    var lastError: String? { storage.lastError?.localizedDescription }
    var fileURL: URL { storage.fileURL }

    init(fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("exclusions.json")) {
        storage = JSONValueStore(fileURL: fileURL, defaultValue: ExclusionsFile(excludedPaths: []))
    }
    @discardableResult func load() -> Bool { storage.load() }
    @MainActor @discardableResult func loadAsync() async -> Bool { await storage.loadAsync() }

    func isExcluded(_ item: LaunchItem) -> Bool {
        let file = storage.value
        let identity = ExclusionIdentity(item: item)
        if file.excludedIdentities.contains(identity) { return true }
        // Legacy paths describe file-backed apps. Empty URL paths must never hide every action.
        guard case let .application(url) = item.launchTarget, !url.path.isEmpty else { return false }
        return file.excludedPaths.contains(url.path)
    }
    @discardableResult func exclude(_ item: LaunchItem) -> Bool {
        storage.mutate { Self.exclude(item, from: &$0) }
    }
    @MainActor @discardableResult func excludeAsync(_ item: LaunchItem) async -> Bool {
        await storage.mutateAsync { Self.exclude(item, from: &$0) }
    }
    @discardableResult func remove(path: String) -> Bool {
        storage.mutate { Self.remove(path: path, from: &$0) }
    }
    @MainActor @discardableResult func removeAsync(path: String) async -> Bool {
        await storage.mutateAsync { Self.remove(path: path, from: &$0) }
    }
    func sortedPaths() -> [String] {
        let file = storage.value
        return (file.excludedPaths + file.excludedIdentities.map(\.selectionKey)).sorted()
    }
    private static func exclude(_ item: LaunchItem, from file: inout ExclusionsFile) {
        if case let .application(url) = item.launchTarget {
            file.excludedPaths = Set(file.excludedPaths).union([url.path]).sorted()
        } else {
            let identity = ExclusionIdentity(item: item)
            if !file.excludedIdentities.contains(identity) { file.excludedIdentities.append(identity) }
        }
    }
    private static func remove(path: String, from file: inout ExclusionsFile) {
        file.excludedPaths.removeAll { $0 == path }
        file.excludedIdentities.removeAll { $0.selectionKey == path }
    }
}
