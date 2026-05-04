struct LauncherRowActionVisibilityPolicy: Equatable {
    let hasAction: Bool

    var isVisible: Bool {
        hasAction
    }

    var allowsHitTesting: Bool {
        isVisible
    }
}
