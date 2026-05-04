import Foundation

final class FileBrowserStore {
    private let fileManager: FileManager
    private(set) var state: FileBrowserPersistedState
    let fileURL: URL

    init(
        fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("file-browser.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.state = .defaultValue
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            state = .defaultValue
            return
        }

        do {
            state = try JSONDecoder().decode(FileBrowserPersistedState.self, from: data)
        } catch {
            NSLog("Bucky could not read file browser state at %@: %@", fileURL.path, error.localizedDescription)
            state = .defaultValue
        }
    }

    func update(_ nextState: FileBrowserPersistedState) {
        state = nextState
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
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save file browser state at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
