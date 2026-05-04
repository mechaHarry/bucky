enum ToolResultsSnapshotPolicy {
    enum Update: Equatable {
        case immediate
    }

    enum Animation: Equatable {
        case none
        case subtle
    }

    static func update(for _: LauncherMode, query _: String) -> Update {
        .immediate
    }

    static func animation(for mode: LauncherMode, items: [ToolItem]) -> Animation {
        guard mode == .tools,
              items.contains(where: { $0.kind == .dictionary }) else {
            return .none
        }

        return .subtle
    }
}
