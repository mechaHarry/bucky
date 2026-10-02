import Foundation

final class SettingsStore {
    private let storage: JSONValueStore<BuckySettings>
    var settings: BuckySettings { storage.value }
    var lastError: String? { storage.lastError?.localizedDescription }
    var fileURL: URL { storage.fileURL }

    init(fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("settings.json")) {
        storage = JSONValueStore(fileURL: fileURL, defaultValue: .defaultValue)
    }
    @discardableResult func load() -> Bool { storage.load() }
    @MainActor @discardableResult func loadAsync() async -> Bool { await storage.loadAsync() }
    @discardableResult func updateHotKey(_ hotKey: HotKeyConfiguration) -> Bool {
        storage.mutate { $0.hotKey = hotKey }
    }
    @discardableResult func updateLaunchAtStartup(_ enabled: Bool) -> Bool {
        storage.mutate { $0.launchAtStartup = enabled }
    }
    @discardableResult func updateAnimationTiming(_ timing: LauncherAnimationTiming) -> Bool {
        storage.mutate { $0.animationTiming = timing }
    }
    @discardableResult func updateFileBrowserStartDirectory(_ directory: URL?) -> Bool {
        storage.mutate { $0.fileBrowserStartDirectory = directory }
    }
    @discardableResult func updateCustomActions(_ actions: [CustomAction]) -> Bool {
        storage.mutate { $0.customActions = actions }
    }
    @MainActor @discardableResult
    func updateHotKeyAsync(_ hotKey: HotKeyConfiguration) async -> Bool {
        await storage.mutateAsync { $0.hotKey = hotKey }
    }
    @MainActor @discardableResult
    func updateLaunchAtStartupAsync(_ enabled: Bool) async -> Bool {
        await storage.mutateAsync { $0.launchAtStartup = enabled }
    }
    @MainActor @discardableResult
    func updateAnimationTimingAsync(_ timing: LauncherAnimationTiming) async -> Bool {
        await storage.mutateAsync { $0.animationTiming = timing }
    }
    @MainActor @discardableResult
    func updateFileBrowserStartDirectoryAsync(_ directory: URL?) async -> Bool {
        await storage.mutateAsync { $0.fileBrowserStartDirectory = directory }
    }
    @MainActor @discardableResult
    func updateCustomActionsAsync(_ actions: [CustomAction]) async -> Bool {
        await storage.mutateAsync { $0.customActions = actions }
    }
}
