import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsStore {
    private let fileManager = FileManager.default
    private(set) var settings: BuckySettings
    let fileURL: URL

    init() {
        fileURL = BuckyPaths.appSupportDirectory.appendingPathComponent("settings.json")
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

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
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
