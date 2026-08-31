import Foundation

@MainActor
final class DictionaryStone {
    typealias Lookup = @Sendable (String) -> [DictionaryResult]

    private let historyStore: DictionaryHistoryStore
    private let lookup: Lookup
    private var requestGate = StoneResultRequestGate()

    init(historyStore: DictionaryHistoryStore, lookup: @escaping Lookup) {
        self.historyStore = historyStore
        self.lookup = lookup
    }

    func snapshot(for query: String) -> StoneResultSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            requestGate.cancel()
            return Self.historySnapshot(for: historyStore.words)
        }

        _ = requestGate.begin(query: trimmedQuery)
        return .loading(message: "Searching Dictionary")
    }

    func lookupResults(for query: String) async -> StoneResultSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return snapshot(for: trimmedQuery)
        }

        let token = requestGate.begin(query: trimmedQuery)
        let lookup = lookup
        let results = await Task.detached(priority: .userInitiated) {
            lookup(trimmedQuery)
        }.value

        guard !Task.isCancelled,
              requestGate.accepts(token, currentQuery: trimmedQuery) else {
            return .loading(message: "Searching Dictionary")
        }

        return Self.lookupSnapshot(for: results, query: trimmedQuery)
    }

    func cancelLookup() {
        requestGate.cancel()
    }

    func activation(for row: StoneResultRow) -> StoneActivation {
        switch row.kind {
        case .dictionary, .dictionaryHistory:
            return Self.dictionaryActivation(for: row.display)
        case .application, .calculation, .calculationHistory, .message, .file:
            return .none
        }
    }

    static func historySnapshot(for entries: [DictionaryHistoryEntry]) -> StoneResultSnapshot {
        .loaded(rows: entries.map(historyRow))
    }

    static func lookupSnapshot(for results: [DictionaryResult], query: String) -> StoneResultSnapshot {
        let rows = resultRows(for: results, query: query)
        if rows.isEmpty {
            return .message(noMatchesRow(for: query))
        }

        return .loaded(rows: rows)
    }

    static func historyRow(for entry: DictionaryHistoryEntry) -> StoneResultRow {
        let id = StoneResultRow.ID.tool(kind: .dictionaryHistory, key: "history:\(entry.id.uuidString)")
        let primaryActivation = dictionaryActivation(for: entry.term)
        return StoneResultRow(
            id: id,
            display: entry.term,
            subtitle: "Opened \(dateFormatter.string(from: entry.date))",
            copyText: nil,
            kind: .dictionaryHistory,
            primaryActivation: primaryActivation,
            accessoryActivation: .removeHistory(id)
        )
    }

    static func resultRows(for results: [DictionaryResult], query: String) -> [StoneResultRow] {
        var seenTerms = Set<String>()
        return results.compactMap { result in
            let trimmedTerm = result.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTerm = normalized(trimmedTerm)
            guard !normalizedTerm.isEmpty,
                  seenTerms.insert(normalizedTerm).inserted else {
                return nil
            }

            let definition = singleLine(result.definition)
            guard !definition.isEmpty else { return nil }

            let primaryActivation = dictionaryActivation(for: trimmedTerm)
            return StoneResultRow(
                id: .tool(kind: .dictionary, key: "term:\(normalizedTerm)"),
                display: trimmedTerm,
                subtitle: definition,
                copyText: nil,
                kind: .dictionary,
                primaryActivation: primaryActivation,
                accessoryActivation: primaryActivation
            )
        }
    }

    private static func noMatchesRow(for query: String) -> StoneResultRow {
        StoneResultRow(
            id: .tool(kind: .message, key: "message:No dictionary matches:\(query)"),
            display: "No dictionary matches",
            subtitle: query,
            copyText: nil,
            kind: .message,
            primaryActivation: .none,
            accessoryActivation: .none
        )
    }

    private static func dictionaryActivation(for term: String) -> StoneActivation {
        guard let escapedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://\(escapedTerm)") else {
            return .none
        }

        return .open(.url(url))
    }

    private static func singleLine(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
