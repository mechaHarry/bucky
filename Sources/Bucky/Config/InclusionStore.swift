import Foundation

final class InclusionStore {
    private let fileManager = FileManager.default
    private(set) var includedPaths = Set<String>()
    let fileURL: URL

    init(fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("inclusions.json")) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        do {
            let file = try JSONFilePersistence.read(
                InclusionsFile.self,
                from: fileURL,
                decoder: JSONFilePersistence.makeDecoder()
            )
            includedPaths = Set(file.includedPaths)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            includedPaths = []
            save()
        } catch {
            NSLog("Bucky could not read inclusions at %@: %@", fileURL.path, error.localizedDescription)
            includedPaths = []
            save()
        }
    }

    func add(path: String) {
        includedPaths.insert(path)
        save()
    }

    func remove(path: String) {
        includedPaths.remove(path)
        save()
    }

    func sortedPaths() -> [String] {
        includedPaths.sorted()
    }

    private func save() {
        do {
            try JSONFilePersistence.write(
                InclusionsFile(includedPaths: includedPaths.sorted()),
                to: fileURL,
                fileManager: fileManager,
                encoder: JSONFilePersistence.makeEncoder()
            )
        } catch {
            NSLog("Bucky could not save inclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
