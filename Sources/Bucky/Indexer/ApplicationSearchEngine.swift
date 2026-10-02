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
        guard !normalizedQuery.isEmpty else {
            return ids
        }

        let queryTokens = tokens(for: normalizedQuery)

        return ids.indices.compactMap { index -> RankedApplicationMatch? in
            guard let item = rowStore.item(for: ids[index]),
                  queryTokens.allSatisfy({ item.searchText.contains($0) }) else {
                return nil
            }

            return RankedApplicationMatch(
                sourceIndex: index,
                title: item.title,
                score: score(item: item, tokens: queryTokens),
                titleOrder: rowStore.titleOrder(for: ids[index])
            )
        }
        .sorted(by: ranksBefore)
        .map { ids[$0.sourceIndex] }
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
