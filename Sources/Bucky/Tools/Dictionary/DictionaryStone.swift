import Foundation

@MainActor
final class DictionaryStone: TextStoneProvider {
    typealias Lookup = @Sendable (String) -> [DictionaryResult]

    private let historyStore: DictionaryHistoryStore
    private let lookup: Lookup
    private let openHandler: @MainActor (String) -> Void
    private var requestGate = StoneResultRequestGate()
    private var activeRequest: StoneResultRequestGate.Token?
    private var activeLookup: ActiveLookup?

    init(
        historyStore: DictionaryHistoryStore,
        lookup: @escaping Lookup,
        openHandler: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.historyStore = historyStore
        self.lookup = lookup
        self.openHandler = openHandler
    }

    var definition: StoneDefinition {
        StoneCatalog.definition(for: .dictionary)
    }

    func snapshot(for query: String) -> StoneResultSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            cancel()
            return Self.historySnapshot(for: historyStore.words)
        }

        cancelPendingWaiters()
        activeRequest = requestGate.begin(query: trimmedQuery)
        return .loading(message: "Searching Dictionary")
    }

    func lookupResults(for query: String) async -> StoneResultSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return snapshot(for: trimmedQuery)
        }

        guard let token = activeRequest,
              requestGate.accepts(token, currentQuery: trimmedQuery) else {
            return .loading(message: "Searching Dictionary")
        }

        let results = await results(for: trimmedQuery)

        guard !Task.isCancelled,
              requestGate.accepts(token, currentQuery: trimmedQuery) else {
            return .loading(message: "Searching Dictionary")
        }

        return Self.lookupSnapshot(for: results, query: trimmedQuery)
    }

    func cancelLookup() {
        cancel()
    }

    func cancel() {
        requestGate.cancel()
        activeRequest = nil
        cancelPendingWaiters()
    }

    func activation(for row: StoneResultRow) -> StoneActivation {
        switch row.kind {
        case .dictionary, .dictionaryHistory:
            return Self.dictionaryActivation(for: row.display)
        case .application, .calculation, .calculationHistory, .message, .file:
            return .none
        }
    }

    func updateSnapshot(for query: String) async -> StoneResultSnapshot {
        await lookupResults(for: query)
    }

    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> TextStoneActivationResult {
        switch activation {
        case .open where row.kind == .dictionary || row.kind == .dictionaryHistory:
            historyStore.add(term: row.display)
            openHandler(row.display)
            return .handled(
                shouldRefresh: true,
                resetSelection: row.kind == .dictionaryHistory,
                shouldHide: true
            )
        case let .removeHistory(rowID) where row.kind == .dictionaryHistory && rowID == row.id:
            historyStore.remove(term: row.display)
            return .handled(shouldRefresh: true, resetSelection: true, shouldHide: false)
        case .copy, .open, .removeHistory, .none:
            return .unhandled
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

    private func results(for query: String) async -> [DictionaryResult] {
        while let activeLookup {
            let lookupToWait = activeLookup
            guard let results = await waitForResults(for: lookupToWait) else { return [] }

            guard !Task.isCancelled else { return [] }

            if self.activeLookup?.id == lookupToWait.id {
                self.activeLookup = nil
            }

            guard lookupToWait.query == query else {
                continue
            }

            guard let activeRequest,
                  requestGate.accepts(activeRequest, currentQuery: query) else {
                return results
            }
        }

        guard !Task.isCancelled,
              let activeRequest,
              requestGate.accepts(activeRequest, currentQuery: query) else {
            return []
        }

        let lookup = lookup
        let lookupID = UUID()
        let lookupTask = Task.detached(priority: .userInitiated) {
            lookup(query)
        }
        let nextLookup = ActiveLookup(id: lookupID, query: query, task: lookupTask)
        activeLookup = nextLookup
        Task { @MainActor [weak self, lookupTask] in
            let results = await lookupTask.value
            self?.completeLookup(id: lookupID, results: results)
        }

        return await waitForResults(for: nextLookup) ?? []
    }

    private func waitForResults(for lookup: ActiveLookup) async -> [DictionaryResult]? {
        let waiterID = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                registerLookupWaiter(
                    id: waiterID,
                    lookupID: lookup.id,
                    continuation: continuation
                )
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelLookupWaiter(id: waiterID, lookupID: lookup.id)
            }
        })
    }

    private func registerLookupWaiter(
        id: UUID,
        lookupID: UUID,
        continuation: CheckedContinuation<[DictionaryResult]?, Never>
    ) {
        guard !Task.isCancelled else {
            continuation.resume(returning: nil)
            return
        }

        guard var lookup = activeLookup, lookup.id == lookupID else {
            continuation.resume(returning: nil)
            return
        }

        if let results = lookup.result {
            continuation.resume(returning: results)
            return
        }

        lookup.waiters[id] = continuation
        activeLookup = lookup
    }

    private func cancelLookupWaiter(id: UUID, lookupID: UUID) {
        guard var lookup = activeLookup,
              lookup.id == lookupID,
              let continuation = lookup.waiters.removeValue(forKey: id) else {
            return
        }

        activeLookup = lookup
        continuation.resume(returning: nil)
    }

    private func completeLookup(id: UUID, results: [DictionaryResult]) {
        guard var lookup = activeLookup, lookup.id == id else { return }

        lookup.result = results
        let waiters = lookup.waiters.values
        lookup.waiters.removeAll()
        activeLookup = lookup

        for waiter in waiters {
            waiter.resume(returning: results)
        }
    }

    private func cancelPendingWaiters() {
        guard var lookup = activeLookup else { return }

        let waiters = lookup.waiters.values
        lookup.waiters.removeAll()
        activeLookup = lookup

        for waiter in waiters {
            waiter.resume(returning: nil)
        }
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

private struct ActiveLookup {
    let id: UUID
    let query: String
    let task: Task<[DictionaryResult], Never>
    var result: [DictionaryResult]?
    var waiters: [UUID: CheckedContinuation<[DictionaryResult]?, Never>] = [:]

    init(id: UUID, query: String, task: Task<[DictionaryResult], Never>) {
        self.id = id
        self.query = query
        self.task = task
        result = nil
    }
}
