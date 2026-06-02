import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let inclusionStore = InclusionStore()
    private let exclusionStore = ExclusionStore()
    private let calculationHistoryStore = CalculationHistoryStore()
    private let dictionaryHistoryStore = DictionaryHistoryStore()
    private var launcherController: LauncherControlling?
    private var statusMenuController: StatusMenuController?
    private var hotKeyController: HotKeyController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let launcherController = makeLauncherController() else {
            showUnsupportedOSAlert()
            NSApp.terminate(nil)
            return
        }

        self.launcherController = launcherController

        statusMenuController = StatusMenuController(
            openAction: { [weak launcherController] in launcherController?.show() },
            reindexAction: { [weak launcherController] in launcherController?.reindex() },
            settingsAction: { [weak launcherController] in launcherController?.showSettings() }
        )

        _ = registerHotKey(settingsStore.settings.hotKey)
    }

    @MainActor
    private func makeLauncherController() -> LauncherControlling? {
        if #available(macOS 26.0, *) {
            return LiquidGlassLauncherWindowController(
                settingsStore: settingsStore,
                inclusionStore: inclusionStore,
                exclusionStore: exclusionStore,
                calculationHistoryStore: calculationHistoryStore,
                dictionaryHistoryStore: dictionaryHistoryStore,
                hotKeyChangeHandler: { [weak self] hotKey in
                    self?.registerHotKey(hotKey) ?? false
                }
            )
        }

        return nil
    }

    @MainActor
    private func registerHotKey(_ hotKey: HotKeyConfiguration) -> Bool {
        if hotKeyController?.configuration == hotKey {
            return true
        }

        do {
            let controller = try HotKeyController(configuration: hotKey) { [weak self] in
                Task { @MainActor in
                    self?.launcherController?.toggle()
                }
            }
            hotKeyController = controller
            return true
        } catch {
            showHotKeyAlert(error, hotKey: hotKey)
            return false
        }
    }

    @MainActor
    private func showHotKeyAlert(_ error: Error, hotKey: HotKeyConfiguration) {
        let alert = NSAlert()
        alert.messageText = "Bucky could not register \(hotKey.displayName)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    @MainActor
    private func showUnsupportedOSAlert() {
        let alert = NSAlert()
        alert.messageText = "Bucky requires macOS 26"
        alert.informativeText = "The legacy AppKit launcher has been removed. Bucky now uses the SwiftUI Liquid Glass launcher only."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
