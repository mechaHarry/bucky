import Foundation

@MainActor
final class CountdownStone: InlineCreationStoneProvider {
    static let refreshIntervalNanoseconds: UInt64 = 50_000_000

    private let store: CountdownStore
    private let now: () -> Date

    init(store: CountdownStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    var definition: StoneDefinition {
        StoneDefinition(
            id: .countdowns,
            shortcutNumber: 5,
            presentation: StonePresentation(
                title: "Countdowns",
                placeholder: "Manage Countdowns",
                systemImage: "timer"
            ),
            surface: .sharedResults,
            updatePolicy: .immediate,
            tint: StoneTint(
                activeHex: 0x34C759,
                panelHex: 0x1E7A3A,
                iconHex: 0x0B5D2A,
                darkModeIconHex: 0x8FF0A8
            ),
            animatesResultUpdates: false
        )
    }

    var inlineCreationConfiguration: StoneInlineCreationConfiguration {
        StoneInlineCreationConfiguration(
            namePlaceholder: "Countdown name",
            targetDateLabel: "Target date and time",
            submitHelp: "Add countdown",
            systemImage: "timer",
            defaultTargetDate: now().addingTimeInterval(3_600)
        )
    }

    func snapshot(for query: String) -> StoneResultSnapshot {
        .loaded(rows: Self.rows(for: store.countdowns, now: now()))
    }

    func updateSnapshot(for query: String) async -> StoneResultSnapshot {
        snapshot(for: query)
    }

    func cancel() {}

    func activation(for row: StoneResultRow) -> StoneActivation {
        row.primaryActivation
    }

    func submitInlineCreation(name: String, targetDate: Date) -> Bool {
        guard targetDate > now(), store.add(name: name, targetDate: targetDate) != nil else {
            return false
        }
        return true
    }

    var inlineCreationError: String? { store.lastError }

    func submitInlineCreationAsync(name: String, targetDate: Date) async -> Bool {
        guard targetDate > now() else { return false }
        return await store.addAsync(name: name, targetDate: targetDate) != nil
    }

    func performAsync(_ activation: StoneActivation, for row: StoneResultRow) async -> StoneProviderActivationResult {
        if case let .providerAction(action) = activation,
           let id = id(from: action, prefix: "delete-confirm:") {
            guard await store.removeAsync(id: id) else {
                return .failed(message: store.lastError ?? "Could not delete this countdown.")
            }
            return .handled(shouldRefresh: true, resetSelection: true, shouldHide: false)
        }
        return perform(activation, for: row)
    }

    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> StoneProviderActivationResult {
        guard case let .providerAction(action) = activation else { return .unhandled }

        if let id = id(from: action, prefix: "delete:") {
            return .confirmation(StoneProviderConfirmation(
                title: "Delete countdown?",
                message: "Return deletes this countdown. Escape cancels.",
                confirmationActivation: .providerAction("delete-confirm:\(id.uuidString)")
            ))
        }

        if let id = id(from: action, prefix: "delete-confirm:") {
            guard store.remove(id: id) else {
                return .failed(message: store.lastError ?? "Could not delete this countdown.")
            }
            return .handled(shouldRefresh: true, resetSelection: true, shouldHide: false)
        }

        return .unhandled
    }

    static func rows(for countdowns: [Countdown], now: Date) -> [StoneResultRow] {
        let countdownRows = countdowns.map { countdown in
            StoneResultRow(
                id: .tool(kind: .message, key: "countdown:\(countdown.id.uuidString)"),
                display: countdown.name,
                subtitle: CountdownRemaining(until: countdown.targetDate, now: now).displayString,
                copyText: nil,
                kind: .message,
                primaryActivation: .none,
                accessoryActivation: .providerAction("delete:\(countdown.id.uuidString)"),
                iconSystemImage: "timer",
                accessoryText: "Target \(targetDateFormatter.string(from: countdown.targetDate))",
                accessoryPresentation: .init(systemImage: "trash", help: "Delete countdown"),
                countdownTarget: countdown.targetDate
            )
        }

        return countdownRows
    }

    private func id(from action: String, prefix: String) -> UUID? {
        guard action.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(action.dropFirst(prefix.count)))
    }

    private static let targetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
