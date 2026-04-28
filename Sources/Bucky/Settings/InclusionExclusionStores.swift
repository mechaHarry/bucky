import Foundation

final class ExclusionStore {
    private let fileManager = FileManager.default
    private(set) var excludedPaths = Set<String>()
    let fileURL: URL

    init() {
        fileURL = BuckyPaths.appSupportDirectory
            .appendingPathComponent("exclusions.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            excludedPaths = []
            return
        }

        do {
            let file = try JSONDecoder().decode(ExclusionsFile.self, from: data)
            excludedPaths = Set(file.excludedPaths)
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
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let file = ExclusionsFile(excludedPaths: excludedPaths.sorted())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save exclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
final class InclusionStore {
    private let fileManager = FileManager.default
    private(set) var includedPaths = Set<String>()
    let fileURL: URL

    private static let defaultIncludedPaths: Set<String> = [
        "/System/Library/CoreServices/Finder.app"
    ]

    init() {
        fileURL = BuckyPaths.appSupportDirectory
            .appendingPathComponent("inclusions.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            includedPaths = Self.defaultIncludedPaths
            save()
            return
        }

        do {
            let file = try JSONDecoder().decode(InclusionsFile.self, from: data)
            includedPaths = Set(file.includedPaths)
        } catch {
            NSLog("Bucky could not read inclusions at %@: %@", fileURL.path, error.localizedDescription)
            includedPaths = Self.defaultIncludedPaths
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
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let file = InclusionsFile(includedPaths: includedPaths.sorted())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save inclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
