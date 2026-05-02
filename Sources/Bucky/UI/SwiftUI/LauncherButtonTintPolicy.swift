struct LauncherButtonTintPolicy: Equatable {
    static let selectedTintOpacity = 0.22
    static let selectedWashOpacity = 0.36

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

    var washOpacity: Double {
        if isSelected {
            return Self.selectedWashOpacity
        }
        if isHovered {
            return Self.selectedWashOpacity / 2
        }
        return 0
    }
}
