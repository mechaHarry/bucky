import Foundation

final class SystemSettingsIndexer {
    static let defaultExtensionRoots = [
        URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications/System Settings.app/Contents/PlugIns", isDirectory: true)
    ]

    private let fileManager: FileManager
    private let sidebarURL: URL
    private let extensionRoots: [URL]

    init(
        fileManager: FileManager = .default,
        sidebarURL: URL = URL(
            fileURLWithPath: "/System/Applications/System Settings.app/Contents/Resources/Sidebar.plist"
        ),
        extensionRoots: [URL] = SystemSettingsIndexer.defaultExtensionRoots
    ) {
        self.fileManager = fileManager
        self.sidebarURL = sidebarURL
        self.extensionRoots = extensionRoots
    }

    func load() -> [LaunchItem] {
        let sidebarBundleIDs = loadSidebarBundleIDs()
        guard !sidebarBundleIDs.isEmpty else { return [] }

        let extensionsByBundleID = loadSettingsExtensions()
        var items: [LaunchItem] = []
        var seenBundleIDs = Set<String>()

        for bundleID in sidebarBundleIDs {
            guard seenBundleIDs.insert(bundleID).inserted,
                  let settingsExtension = extensionsByBundleID[bundleID],
                  let launchURL = URL(string: "x-apple.systempreferences:\(bundleID)") else {
                continue
            }

            items.append(LaunchItem(
                title: settingsExtension.displayName,
                subtitle: "System Settings",
                url: settingsExtension.url,
                launchTarget: .url(launchURL),
                category: .settings,
                searchText: normalized("\(settingsExtension.displayName) System Settings")
            ))
        }

        return items
    }

    private func loadSidebarBundleIDs() -> [String] {
        guard let propertyList = propertyList(at: sidebarURL) as? [[String: Any]] else {
            return []
        }

        return propertyList.flatMap { section -> [String] in
            section["content"] as? [String] ?? []
        }
    }

    private func loadSettingsExtensions() -> [String: SettingsExtension] {
        var extensionsByBundleID: [String: SettingsExtension] = [:]

        for root in extensionRoots where fileManager.fileExists(atPath: root.path) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children where child.pathExtension == "appex" {
                guard let settingsExtension = settingsExtension(at: child) else {
                    continue
                }
                extensionsByBundleID[settingsExtension.bundleID] = settingsExtension
            }
        }

        return extensionsByBundleID
    }

    private func settingsExtension(at url: URL) -> SettingsExtension? {
        let infoURL = url
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")

        guard let info = propertyList(at: infoURL) as? [String: Any],
              let bundleID = nonEmpty(info["CFBundleIdentifier"] as? String),
              allowsSystemPreferencesURL(info) else {
            return nil
        }

        let bundle = Bundle(url: url)
        let displayName = nonEmpty(bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? nonEmpty(bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? nonEmpty(info["CFBundleDisplayName"] as? String)
            ?? nonEmpty(info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        return SettingsExtension(bundleID: bundleID, displayName: displayName, url: url)
    }

    private func allowsSystemPreferencesURL(_ info: [String: Any]) -> Bool {
        let extensionAttributes = info["EXAppExtensionAttributes"] as? [String: Any]
        let settingsAttributes = extensionAttributes?["SettingsExtensionAttributes"] as? [String: Any]
        return settingsAttributes?["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true
    }

    private func propertyList(at url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct SettingsExtension {
    let bundleID: String
    let displayName: String
    let url: URL
}
