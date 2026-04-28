import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let inclusionStore = InclusionStore()
    private let exclusionStore = ExclusionStore()
    private let calculationHistoryStore = CalculationHistoryStore()
    private var launcherController: LauncherControlling?
    private var settingsWindowController: SettingsWindowController?
    private var statusMenuController: StatusMenuController?
    private var hotKeyController: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let launcherController = makeLauncherController()
        self.launcherController = launcherController

        statusMenuController = StatusMenuController(
            openAction: { [weak launcherController] in launcherController?.show() },
            reindexAction: { [weak launcherController] in launcherController?.reindex() },
            settingsAction: { [weak self] in self?.showSettings() }
        )

        _ = registerHotKey(settingsStore.settings.hotKey)
    }

    private func makeLauncherController() -> LauncherControlling {
        if #available(macOS 26.0, *),
           ProcessInfo.processInfo.environment["BUCKY_FORCE_APPKIT_UI"] != "1" {
            return LiquidGlassLauncherWindowController(
                inclusionStore: inclusionStore,
                exclusionStore: exclusionStore,
                calculationHistoryStore: calculationHistoryStore,
                openSettingsAction: { [weak self] in self?.showSettings() }
            )
        }

        return LauncherWindowController(
            inclusionStore: inclusionStore,
            exclusionStore: exclusionStore,
            calculationHistoryStore: calculationHistoryStore,
            openSettingsAction: { [weak self] in self?.showSettings() }
        )
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                inclusionStore: inclusionStore,
                exclusionStore: exclusionStore,
                hotKeyChangeHandler: { [weak self] hotKey in
                    self?.registerHotKey(hotKey) ?? false
                },
                inclusionsChangedHandler: { [weak self] in
                    self?.launcherController?.refreshAfterInclusionsChanged()
                },
                exclusionsChangedHandler: { [weak self] in
                    self?.launcherController?.refreshAfterExclusionsChanged()
                }
            )
        }

        settingsWindowController?.show()
    }

    private func registerHotKey(_ hotKey: HotKeyConfiguration) -> Bool {
        if hotKeyController?.configuration == hotKey {
            return true
        }

        do {
            let controller = try HotKeyController(configuration: hotKey) { [weak self] in
                self?.launcherController?.toggle()
            }
            hotKeyController = controller
            return true
        } catch {
            showHotKeyAlert(error, hotKey: hotKey)
            return false
        }
    }

    private func showHotKeyAlert(_ error: Error, hotKey: HotKeyConfiguration) {
        let alert = NSAlert()
        alert.messageText = "Bucky could not register \(hotKey.displayName)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
