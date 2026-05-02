struct LauncherButtonTintPolicy: Equatable {
    static let selectedTintOpacity = 0.22

    let isSelected: Bool
    let isHovered: Bool

    var tintOpacity: Double {
        if isSelected {
            return Self.selectedTintOpacity
        }
        if isHovered {
            return Self.selectedTintOpacity / 2
        }
        return 0
    }
}
