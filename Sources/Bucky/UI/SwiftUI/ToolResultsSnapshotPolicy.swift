enum ToolResultsSnapshotPolicy {
    enum Update: Equatable {
        case immediate
    }

    static func update(for _: LauncherMode, query _: String) -> Update {
        .immediate
    }
}
