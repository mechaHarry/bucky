import Foundation

final class ApplicationIndexer {
    static let defaultRoots = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
    ]

    private let fileManager: FileManager
    private let roots: [URL]
    private let systemSettingsItemsProvider: () -> [LaunchItem]
    private let customActionsProvider: () -> [CustomAction]

    init(
        fileManager: FileManager = .default,
        roots: [URL] = ApplicationIndexer.defaultRoots,
        systemSettingsItemsProvider: @escaping () -> [LaunchItem] = { SystemSettingsIndexer().load() },
        customActionsProvider: @escaping () -> [CustomAction] = { SettingsStore().settings.customActions }
    ) {
        self.fileManager = fileManager
        self.roots = roots
        self.systemSettingsItemsProvider = systemSettingsItemsProvider
        self.customActionsProvider = customActionsProvider
    }

    func load(includedPaths: Set<String>) -> [LaunchItem] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .localizedNameKey
        ]

        var items: [LaunchItem] = []
        var seenPaths = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            if shouldScanDirectApplicationsOnly(root) {
                loadDirectApplications(from: root, into: &items, seenPaths: &seenPaths)
            } else {
                loadRecursiveApplications(from: root, keys: keys, into: &items, seenPaths: &seenPaths)
            }
        }

        for path in includedPaths.sorted() {
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.lowercased() == "app",
                  fileManager.fileExists(atPath: url.path),
                  seenPaths.insert(url.path).inserted,
                  let item = applicationItem(for: url) else {
                continue
            }
            items.append(item)
        }

        items.append(contentsOf: systemSettingsItemsProvider())
        items.append(contentsOf: CustomActionIndexer().load(actions: customActionsProvider()))

        return items.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func loadDirectApplications(
        from root: URL,
        into items: inout [LaunchItem],
        seenPaths: inout Set<String>
    ) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children where child.pathExtension.lowercased() == "app" {
            if seenPaths.insert(child.path).inserted, let item = applicationItem(for: child) {
                items.append(item)
            }
        }
    }

    private func loadRecursiveApplications(
        from root: URL,
        keys: [URLResourceKey],
        into items: inout [LaunchItem],
        seenPaths: inout Set<String>
    ) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                NSLog("Bucky index skipped %@: %@", url.path, error.localizedDescription)
                return true
            }
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let extensionName = url.pathExtension.lowercased()

            if extensionName == "app" {
                if seenPaths.insert(url.path).inserted, let item = applicationItem(for: url) {
                    items.append(item)
                }
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            if values.isDirectory == true {
                continue
            }
        }
    }

    private func shouldScanDirectApplicationsOnly(_ root: URL) -> Bool {
        root.standardizedFileURL.path.hasSuffix("/CoreServices")
    }

    private func applicationItem(for url: URL) -> LaunchItem? {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let title = nonEmpty(displayName)
            ?? nonEmpty(bundleName)
            ?? url.deletingPathExtension().lastPathComponent

        return LaunchItem(
            title: title,
            subtitle: url.path,
            url: url,
            searchText: normalized(title)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
