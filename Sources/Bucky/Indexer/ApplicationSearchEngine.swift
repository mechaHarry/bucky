import Foundation

struct ApplicationSearchCandidate: Hashable {
    let sourceIndex: Int
    let title: String
    let searchText: String

    init(sourceIndex: Int, title: String, searchText: String) {
        self.sourceIndex = sourceIndex
        self.title = title
        self.searchText = searchText
    }

    init(sourceIndex: Int, item: LaunchItem) {
        self.init(sourceIndex: sourceIndex, title: item.title, searchText: item.searchText)
    }
}

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
                score: score(title: item.title, tokens: queryTokens)
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
                score: score(title: item.title, tokens: queryTokens)
            )
        }
        .sorted(by: ranksBefore)
        .map { ids[$0.sourceIndex] }
    }

    static func rankedCandidates(
        _ candidates: [ApplicationSearchCandidate],
        normalizedQuery: String
    ) -> [ApplicationSearchCandidate] {
        guard !normalizedQuery.isEmpty else {
            return candidates
        }

        let queryTokens = tokens(for: normalizedQuery)

        return candidates.compactMap { candidate -> (ApplicationSearchCandidate, RankedApplicationMatch)? in
            guard queryTokens.allSatisfy({ candidate.searchText.contains($0) }) else {
                return nil
            }

            return (
                candidate,
                RankedApplicationMatch(
                    sourceIndex: candidate.sourceIndex,
                    title: candidate.title,
                    score: score(title: candidate.title, tokens: queryTokens)
                )
            )
        }
        .sorted { ranksBefore($0.1, $1.1) }
        .map(\.0)
    }

    private static func ranksBefore(_ left: RankedApplicationMatch, _ right: RankedApplicationMatch) -> Bool {
        if left.score != right.score {
            return left.score > right.score
        }

        let titleOrder = left.title.localizedStandardCompare(right.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return left.sourceIndex < right.sourceIndex
    }

    private static func score(title originalTitle: String, tokens: [String]) -> Int {
        let title = normalized(originalTitle)
        var titleWords: [String.SubSequence]?
        var score = 0

        for token in tokens {
            if title == token {
                score += 1200
            } else if title.hasPrefix(token) {
                score += 1000
            } else if words(in: title, cachedWords: &titleWords).contains(where: { $0.hasPrefix(token) }) {
                score += 850
            } else if title.contains(token) {
                score += 650
            } else {
                score += 350
            }
        }

        score -= min(originalTitle.count, 120)
        return score
    }

    private static func words(
        in title: String,
        cachedWords: inout [String.SubSequence]?
    ) -> [String.SubSequence] {
        if let cachedWords {
            return cachedWords
        }

        let words = title.split(separator: " ")
        cachedWords = words
        return words
    }
}

private struct RankedApplicationMatch {
    let sourceIndex: Int
    let title: String
    let score: Int
}
