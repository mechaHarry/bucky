import Foundation

final class ExclusionStore {
    private let fileManager = FileManager.default
    private(set) var excludedPaths = Set<String>()
    let fileURL: URL

    init(fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("exclusions.json")) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        do {
            let file = try JSONFilePersistence.read(
                ExclusionsFile.self,
                from: fileURL,
                decoder: JSONFilePersistence.makeDecoder()
            )
            excludedPaths = Set(file.excludedPaths)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            excludedPaths = []
        } catch {
            NSLog("Bucky could not read exclusions at %@: %@", fileURL.path, error.localizedDescription)
            excludedPaths = []
        }
    }

    func isExcluded(_ item: LaunchItem) -> Bool {
        excludedPaths.contains(item.url.path)
    }

    func exclude(_ item: LaunchItem) {
        excludedPaths.insert(item.url.path)
        save()
    }

    func remove(path: String) {
        excludedPaths.remove(path)
        save()
    }

    func sortedPaths() -> [String] {
        excludedPaths.sorted()
    }

    private func save() {
        do {
            try JSONFilePersistence.write(
                ExclusionsFile(excludedPaths: excludedPaths.sorted()),
                to: fileURL,
                fileManager: fileManager,
                encoder: JSONFilePersistence.makeEncoder()
            )
        } catch {
            NSLog("Bucky could not save exclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
