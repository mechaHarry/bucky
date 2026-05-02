struct LauncherRowActionVisibilityPolicy: Equatable {
    let hasAction: Bool
    let isSelected: Bool
    let isHovered: Bool

    var isVisible: Bool {
        hasAction && (isSelected || isHovered)
    }

    var allowsHitTesting: Bool {
        isVisible
    }
}
