import Foundation

@MainActor
final class CalculatorStone: HistoryStoneProvider {
    private let store: CalculationHistoryStore
    private var pendingHistoryTask: Task<Void, Never>?
    private var pendingHistory: (expression: String, result: String)?
    var historyChanged: (() -> Void)?

    init(store: CalculationHistoryStore) { self.store = store }
    deinit { pendingHistoryTask?.cancel() }

    var definition: StoneDefinition { StoneCatalog.definition(for: .calculator) }
    var canClearHistory: Bool { !store.calculations.isEmpty }
    var historyError: String? { store.lastError }

    func snapshot(for query: String) -> StoneResultSnapshot {
        snapshot(for: query, recordingHistory: true)
    }

    func snapshot(for query: String, recordingHistory: Bool) -> StoneResultSnapshot {
        let items = tools(for: query.trimmingCharacters(in: .whitespacesAndNewlines), recordingHistory: recordingHistory)
        guard !items.isEmpty else { return .empty(message: "No calculation history") }
        let rows = items.map(StoneResultRow.tool)
        return rows.count == 1 && rows[0].kind == .message ? .message(rows[0]) : .loaded(rows: rows)
    }

    func updateSnapshot(for query: String) async -> StoneResultSnapshot { snapshot(for: query) }
    func cancel() {
        pendingHistoryTask?.cancel()
        pendingHistoryTask = nil
        pendingHistory = nil
    }
    func activation(for row: StoneResultRow) -> StoneActivation { row.primaryActivation }
    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> StoneProviderActivationResult {
        if case .copy = activation, row.kind == .calculation { commitPendingHistory() }
        return .unhandled
    }

    func clearHistory() async -> Bool {
        cancel()
        return await store.clearAsync()
    }

    private func tools(for query: String, recordingHistory: Bool) -> [ToolItem] {
        if recordingHistory { cancel() }
        guard !query.isEmpty else { return historyItems() }
        let expression = ArithmeticEvaluator.normalizedExpression(query)
        guard ArithmeticEvaluator.isArithmeticInput(expression) else {
            return [ToolItem(title: "Enter a calculation", subtitle: query, copyText: nil, kind: .message)]
        }
        guard let result = ArithmeticEvaluator.evaluate(expression) else {
            return [ToolItem(title: "Complete the calculation", subtitle: query, copyText: nil, kind: .message)] + historyItems()
        }
        if recordingHistory, ArithmeticEvaluator.shouldStoreInHistory(expression) {
            pendingHistory = (expression, result)
            pendingHistoryTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 700_000_000) } catch { return }
                self?.commitPendingHistory()
            }
        }
        return [ToolItem(title: result, subtitle: "\(expression) =", copyText: result, kind: .calculation)]
            + historyItems(excluding: expression, result: result)
    }

    private func historyItems(excluding expression: String? = nil, result: String? = nil) -> [ToolItem] {
        store.calculations.compactMap { entry in
            guard entry.expression != expression || entry.result != result else { return nil }
            return ToolItem(
                title: "\(entry.expression) = \(entry.result)",
                subtitle: "Calculated \(Self.dateFormatter.string(from: entry.date))",
                copyText: entry.result,
                kind: .calculationHistory
            )
        }
    }

    private func commitPendingHistory() {
        guard let pending = pendingHistory else { return }
        cancel()
        Task { [weak self, store] in
            _ = await store.addAsync(expression: pending.expression, result: pending.result)
            self?.historyChanged?()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
