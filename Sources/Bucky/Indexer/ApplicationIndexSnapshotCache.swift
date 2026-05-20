import Foundation

struct ApplicationIndexSnapshotCache {
    private let fileURL: URL
    private let fileManager: FileManager
    private let schemaVersion = 1

    init(
        fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("app-index-snapshot.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> [LaunchItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(ApplicationIndexSnapshot.self, from: data),
              snapshot.schemaVersion == schemaVersion else {
            return []
        }

        return snapshot.items.compactMap(\.launchItem)
    }

    func save(_ items: [LaunchItem]) {
        let snapshot = ApplicationIndexSnapshot(
            schemaVersion: schemaVersion,
            items: items.map(ApplicationIndexSnapshotItem.init)
        )

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save app index snapshot: %@", error.localizedDescription)
        }
    }
}

private struct ApplicationIndexSnapshot: Codable {
    let schemaVersion: Int
    let items: [ApplicationIndexSnapshotItem]
}

private struct ApplicationIndexSnapshotItem: Codable {
    let title: String
    let subtitle: String
    let url: URL
    let launchTarget: SnapshotLaunchTarget
    let category: LaunchItemCategory
    let searchText: String

    init(_ item: LaunchItem) {
        title = item.title
        subtitle = item.subtitle
        url = item.url
        launchTarget = SnapshotLaunchTarget(item.launchTarget)
        category = item.category
        searchText = item.searchText
    }

    var launchItem: LaunchItem? {
        LaunchItem(
            title: title,
            subtitle: subtitle,
            url: url,
            launchTarget: launchTarget.launchTarget,
            category: category,
            searchText: searchText
        )
    }
}

private enum SnapshotLaunchTarget: Codable {
    case application(URL)
    case url(URL)
    case shellCommand(String)

    init(_ launchTarget: LaunchTarget) {
        switch launchTarget {
        case let .application(url):
            self = .application(url)
        case let .url(url):
            self = .url(url)
        case let .shellCommand(command):
            self = .shellCommand(command)
        }
    }

    var launchTarget: LaunchTarget {
        switch self {
        case let .application(url):
            return .application(url)
        case let .url(url):
            return .url(url)
        case let .shellCommand(command):
            return .shellCommand(command)
        }
    }
}
