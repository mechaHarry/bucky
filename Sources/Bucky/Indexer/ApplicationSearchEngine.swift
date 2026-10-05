import Foundation

enum ApplicationSearchEngine {
    static func tokens(for normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func filter(_ items: [LaunchItem], normalizedQuery: String) -> [LaunchItem] {
        guard !normalizedQuery.isEmpty else {
            return items
        }

        let queryTokens = tokens(for: normalizedQuery)

        return items.indices.compactMap { index -> RankedApplicationMatch? in
            let item = items[index]
            guard queryTokens.allSatisfy({ item.searchText.contains($0) }) else {
                return nil
            }

            return RankedApplicationMatch(
                sourceIndex: index,
                title: item.title,
                score: score(item: item, tokens: queryTokens)
            )
        }
        .sorted(by: ranksBefore)
        .map { items[$0.sourceIndex] }
    }

    static func filterIDs(
        _ ids: [AppRowID],
        rowStore: ApplicationRowStore,
        normalizedQuery: String
    ) -> [AppRowID] {
        // Synchronous compatibility path is useful for benchmarks and prebuilt snapshots.
        (try? filterIDsCancellable(ids, rowStore: rowStore, normalizedQuery: normalizedQuery,
                                   cancellationCheck: {})) ?? []
    }

    static func filterIDsCancellable(
        _ ids: [AppRowID],
        rowStore: ApplicationRowStore,
        normalizedQuery: String,
        cancellationCheck: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> [AppRowID] {
        try cancellationCheck()
        guard !normalizedQuery.isEmpty else { return ids }
        let queryTokens = tokens(for: normalizedQuery)
        var matches: [RankedApplicationMatch] = []
        matches.reserveCapacity(min(ids.count, 256))
        for index in ids.indices {
            if index & 63 == 0 { try cancellationCheck() }
            guard let item = rowStore.item(for: ids[index]),
                  queryTokens.allSatisfy({ item.searchText.contains($0) }) else { continue }
            matches.append(RankedApplicationMatch(sourceIndex: index, title: item.title,
                score: score(item: item, tokens: queryTokens),
                titleOrder: rowStore.titleOrder(for: ids[index])))
        }
        try cancellationCheck()
        // Swift's standard sort cannot throw. Merge in bounded chunks so obsolete input
        // yields promptly even when every indexed row matches a broad query.
        var scratch = matches
        var width = 1
        while width < matches.count {
            var start = 0
            while start < matches.count {
                try cancellationCheck()
                let middle = min(start + width, matches.count)
                let end = min(middle + width, matches.count)
                var left = start
                var right = middle
                for output in start..<end {
                    if output & 63 == 0 { try cancellationCheck() }
                    if left < middle && (right == end || !ranksBefore(matches[right], matches[left])) {
                        scratch[output] = matches[left]
                        left += 1
                    } else {
                        scratch[output] = matches[right]
                        right += 1
                    }
                }
                start = end
            }
            swap(&matches, &scratch)
            width *= 2
        }
        var results: [AppRowID] = []
        results.reserveCapacity(matches.count)
        for index in matches.indices {
            if index & 63 == 0 { try cancellationCheck() }
            results.append(ids[matches[index].sourceIndex])
        }
        try cancellationCheck()
        return results
    }

    private static func ranksBefore(_ left: RankedApplicationMatch, _ right: RankedApplicationMatch) -> Bool {
        if left.score != right.score {
            return left.score > right.score
        }

        if let leftOrder = left.titleOrder, let rightOrder = right.titleOrder {
            return leftOrder == rightOrder ? left.sourceIndex < right.sourceIndex : leftOrder < rightOrder
        }
        let titleOrder = left.title.localizedStandardCompare(right.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return left.sourceIndex < right.sourceIndex
    }

    private static func score(item: LaunchItem, tokens: [String]) -> Int {
        let title = item.normalizedTitle
        var score = 0

        for token in tokens {
            if title == token {
                score += 1200
            } else if title.hasPrefix(token) {
                score += 1000
            } else if item.titleWords.contains(where: { $0.hasPrefix(token) }) {
                score += 850
            } else if title.contains(token) {
                score += 650
            } else {
                score += 350
            }
        }

        score -= item.titleLengthPenalty
        return score
    }

}

private struct RankedApplicationMatch {
    let sourceIndex: Int
    let title: String
    let score: Int
    var titleOrder: Int? = nil
}

// A serial Swift executor bounds CPU work to one scan. Cancelled queued requests
// fail their first cancellation check before touching the index.
actor ApplicationSearchWorker {
    func filter(_ ids: [AppRowID], rowStore: ApplicationRowStore, query: String) throws -> [AppRowID] {
        try ApplicationSearchEngine.filterIDsCancellable(ids, rowStore: rowStore, normalizedQuery: query)
    }
}
