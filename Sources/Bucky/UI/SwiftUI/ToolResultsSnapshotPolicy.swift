enum ToolResultsSnapshotPolicy {
    enum Update: Equatable {
        case immediate
        case deferred(delayNanoseconds: UInt64)
    }

    enum Animation: Equatable {
        case none
        case subtle
    }

    static let dictionaryLookupDelayNanoseconds: UInt64 = 80_000_000

    static func update(for mode: LauncherMode, query: String) -> Update {
        if mode == .dictionary,
           !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .deferred(delayNanoseconds: dictionaryLookupDelayNanoseconds)
        }

        return .immediate
    }

    static func animation(for mode: LauncherMode, items: [ToolItem]) -> Animation {
        guard mode == .dictionary,
              items.contains(where: { $0.kind == .dictionary }) else {
            return .none
        }

        return .subtle
    }
}
