import AppKit

@MainActor
final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openAction: @MainActor () -> Void
    private let reindexAction: @MainActor () -> Void
    private let settingsAction: @MainActor () -> Void

    init(
        openAction: @escaping @MainActor () -> Void,
        reindexAction: @escaping @MainActor () -> Void,
        settingsAction: @escaping @MainActor () -> Void
    ) {
        self.openAction = openAction
        self.reindexAction = reindexAction
        self.settingsAction = settingsAction
        super.init()
        buildMenu()
    }

    private func buildMenu() {
        if let button = statusItem.button {
            button.image = nil
            button.title = "🦾"
            button.font = .systemFont(ofSize: 16)
            button.toolTip = "Bucky"
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Bucky", action: #selector(open), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let reindexItem = NSMenuItem(title: "Reindex Applications", action: #selector(reindex), keyEquivalent: "")
        reindexItem.target = self
        menu.addItem(reindexItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Bucky", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func open() {
        openAction()
    }

    @objc private func reindex() {
        reindexAction()
    }

    @objc private func settings() {
        settingsAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
