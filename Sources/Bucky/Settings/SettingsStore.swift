import Foundation

final class SettingsStore {
    private let fileManager = FileManager.default
    private(set) var settings: BuckySettings
    let fileURL: URL

    init(fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("settings.json")) {
        self.fileURL = fileURL
        settings = .defaultValue
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            settings = .defaultValue
            return
        }

        do {
            settings = try JSONDecoder().decode(BuckySettings.self, from: data)
        } catch {
            NSLog("Bucky could not read settings at %@: %@", fileURL.path, error.localizedDescription)
            settings = .defaultValue
        }
    }

    func updateHotKey(_ hotKey: HotKeyConfiguration) {
        settings.hotKey = hotKey
        save()
    }

    func updateLaunchAtStartup(_ enabled: Bool) {
        settings.launchAtStartup = enabled
        save()
    }

    func updateAnimationTiming(_ timing: LauncherAnimationTiming) {
        settings.animationTiming = timing
        save()
    }

    func updateFileBrowserStartDirectory(_ directory: URL?) {
        settings.fileBrowserStartDirectory = directory
        save()
    }

    func updateCustomActions(_ actions: [CustomAction]) {
        settings.customActions = actions
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
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save settings at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
