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
        guard mode == .dictionary,
              items.contains(where: { $0.kind == .dictionary }) else {
            return .none
        }

        return .subtle
    }
}
