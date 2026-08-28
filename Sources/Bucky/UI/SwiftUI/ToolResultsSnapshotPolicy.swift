enum ToolResultsSnapshotPolicy {
    typealias Update = StoneUpdatePolicy

    enum Animation: Equatable {
        case none
        case subtle
    }

    static func update(for mode: LauncherMode, query: String) -> Update {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .immediate
        }

        return mode.stoneDefinition.updatePolicy
    }

    static func animation(for mode: LauncherMode, items: [ToolItem]) -> Animation {
        animation(for: mode, snapshot: .loaded(rows: items.map(StoneResultRow.tool)))
    }

    static func animation(for mode: LauncherMode, snapshot: StoneResultSnapshot) -> Animation {
        guard mode == .dictionary,
              snapshot.rows.contains(where: { $0.kind == .dictionary }) else {
            return .none
        }

        return .subtle
    }
}
