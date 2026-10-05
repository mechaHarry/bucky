import Foundation

struct AppRowID: Hashable {
    let rawValue: Int
}

struct ApplicationRowStore {
    private(set) var allIDs: [AppRowID] = []
    private(set) var visibleIDs: [AppRowID] = []
    private(set) var generation = 0
    private var itemsByID: [AppRowID: LaunchItem] = [:]
    private var titleOrderByID: [AppRowID: Int] = [:]
    private var idByKey: [String: AppRowID] = [:]
    private var nextID = 0

    var isEmpty: Bool {
        allIDs.isEmpty
    }

    mutating func replaceAll(_ items: [LaunchItem]) {
        _ = replaceAllIfChanged(items)
    }

    mutating func replaceAllIfChanged(_ items: [LaunchItem]) -> Bool {
        if allIDs.count == items.count && zip(allIDs, items).allSatisfy({ itemsByID[$0.0] == $0.1 }) {
            return false
        }

        var nextAllIDs: [AppRowID] = []
        var nextItemsByID: [AppRowID: LaunchItem] = [:]
        var nextIDByKey: [String: AppRowID] = [:]

        nextAllIDs.reserveCapacity(items.count)
        nextItemsByID.reserveCapacity(items.count)
        nextIDByKey.reserveCapacity(items.count)
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
        // Locale-aware natural collation is index work, not per-query sort work.
        let titleOrderedIDs = nextAllIDs.sorted {
            nextItemsByID[$0]!.title.localizedStandardCompare(nextItemsByID[$1]!.title) == .orderedAscending
        }
        var rank = 0
        var previousTitle: String?
        titleOrderByID.removeAll(keepingCapacity: true)
        for id in titleOrderedIDs {
            let title = nextItemsByID[id]!.title
            if let previousTitle, previousTitle.localizedStandardCompare(title) != .orderedSame { rank += 1 }
            titleOrderByID[id] = rank
            previousTitle = title
        }
        idByKey = nextIDByKey
        generation += 1
        return true
    }

    // Preparation may overlap a visibility edit. Publication must use a new generation
    // so cached rows and scans cannot accidentally identify two stores as equivalent.
    mutating func advanceGeneration(after latestGeneration: Int) {
        generation = max(generation, latestGeneration + 1)
    }

    mutating func rebuildVisibleIDs(isVisible: (LaunchItem) -> Bool) {
        let nextVisibleIDs = allIDs.filter { id in
            guard let item = itemsByID[id] else { return false }
            return isVisible(item)
        }
        guard nextVisibleIDs != visibleIDs else { return }
        visibleIDs = nextVisibleIDs
        generation += 1
    }

    func item(for id: AppRowID) -> LaunchItem? {
        itemsByID[id]
    }

    func titleOrder(for id: AppRowID) -> Int? { titleOrderByID[id] }

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
