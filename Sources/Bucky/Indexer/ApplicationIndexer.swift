import Foundation

final class ApplicationIndexer {
    private let fileManager = FileManager.default
    private let roots = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
    ]

    func load(includedPaths: Set<String>) -> [LaunchItem] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .localizedNameKey
        ]

        var items: [LaunchItem] = []
        var seenPaths = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { url, error in
                    NSLog("Bucky index skipped %@: %@", url.path, error.localizedDescription)
                    return true
                }
            ) else {
                continue
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

        return items.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
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
