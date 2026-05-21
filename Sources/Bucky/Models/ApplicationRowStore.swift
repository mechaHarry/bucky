import Foundation

struct AppRowID: Hashable {
    let rawValue: Int
}

struct ApplicationRowStore {
    private(set) var allIDs: [AppRowID] = []
    private(set) var visibleIDs: [AppRowID] = []
    private(set) var generation = 0
    private var itemsByID: [AppRowID: LaunchItem] = [:]
    private var idByKey: [String: AppRowID] = [:]
    private var nextID = 0

    var isEmpty: Bool {
        allIDs.isEmpty
    }

    mutating func replaceAll(_ items: [LaunchItem]) {
        _ = replaceAllIfChanged(items)
    }

    mutating func replaceAllIfChanged(_ items: [LaunchItem]) -> Bool {
        if self.items(for: allIDs) == items {
            return false
        }

        var nextAllIDs: [AppRowID] = []
        var nextItemsByID: [AppRowID: LaunchItem] = [:]
        var nextIDByKey: [String: AppRowID] = [:]

        for item in items {
            let key = stableKey(for: item)
            let id = idByKey[key] ?? allocateID()
            nextAllIDs.append(id)
            nextItemsByID[id] = item
            nextIDByKey[key] = id
        }

        allIDs = nextAllIDs
        visibleIDs = nextAllIDs
        itemsByID = nextItemsByID
        idByKey = nextIDByKey
        generation += 1
        return true
    }

    mutating func rebuildVisibleIDs(isVisible: (LaunchItem) -> Bool) {
        visibleIDs = allIDs.filter { id in
            guard let item = itemsByID[id] else { return false }
            return isVisible(item)
        }
    }

    func item(for id: AppRowID) -> LaunchItem? {
        itemsByID[id]
    }

    func items(for ids: [AppRowID]) -> [LaunchItem] {
        ids.compactMap { itemsByID[$0] }
    }

    private mutating func allocateID() -> AppRowID {
        let id = AppRowID(rawValue: nextID)
        nextID += 1
        return id
    }

    private func stableKey(for item: LaunchItem) -> String {
        switch item.launchTarget {
        case let .application(url):
            return "app:\(url.standardizedFileURL.path)"
        case let .url(url):
            return "url:\(url.absoluteString)"
        case let .shellCommand(command):
            return "action:\(item.url.absoluteString):\(command)"
        }
    }
}
