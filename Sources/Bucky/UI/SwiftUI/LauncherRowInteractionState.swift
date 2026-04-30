enum LauncherSelectionTransitionStyle: Equatable {
    case materialize
}

struct LauncherRowInteractionState: Equatable {
    let isSelected: Bool
    let isHovered: Bool

    var usesHoverSurface: Bool {
        isHovered && !isSelected
    }

    var revealsAuxiliaryAction: Bool {
        isSelected || isHovered
    }

    var selectionTransitionStyle: LauncherSelectionTransitionStyle {
        .materialize
    }

    var usesSharedSelectionGlassIdentity: Bool {
        false
    }

    var baseTintOpacity: Double {
        0.075
    }

    var hoverTintOpacity: Double {
        0.16
    }

    var selectionTintOpacity: Double {
        0.22
    }

    var shadowOpacity: Double {
        if isSelected {
            return 0.18
        }
        if isHovered {
            return 0.14
        }
        return 0.09
    }

    var shadowRadius: Double {
        if isSelected {
            return 15
        }
        if isHovered {
            return 12
        }
        return 8
    }

    var shadowY: Double {
        if isSelected {
            return 6
        }
        if isHovered {
            return 5
        }
        return 3
    }

    var borderOpacity: Double {
        if isSelected {
            return 0.44
        }
        if isHovered {
            return 0.24
        }
        return 0.13
    }
}

struct LauncherHeaderInteractionState: Equatable {
    let isHovered: Bool
    let isFocused: Bool
    let isIndexing: Bool

    var isActive: Bool {
        isHovered || isIndexing
    }

    var tintOpacity: Double {
        if isFocused {
            return 0
        }
        if isIndexing {
            return 0.12
        }
        if isHovered {
            return 0.07
        }
        return 0
    }

    var glowOpacity: Double {
        if isIndexing {
            return 0.18
        }
        if isHovered {
            return 0.08
        }
        return 0
    }

    var depthShadowOpacity: Double {
        if isIndexing {
            return 0.18
        }
        if isHovered {
            return 0.15
        }
        return 0.12
    }

    var depthShadowRadius: Double {
        isActive ? 16 : 12
    }

    var depthShadowY: Double {
        isActive ? 7 : 5
    }

    var borderOpacity: Double {
        if isIndexing {
            return 0.32
        }
        if isHovered {
            return 0.24
        }
        return 0.18
    }
}

struct LauncherHeaderControlInteractionState: Equatable {
    let isHovered: Bool
    let isEnabled: Bool

    var symbolOpacity: Double {
        guard isEnabled else { return 0.46 }
        return 1
    }

    var tintOpacity: Double {
        guard isEnabled else { return 0 }
        return isHovered ? 0.18 : 0
    }

    var glowOpacity: Double {
        0
    }

    var fillSymbolOpacity: Double {
        isHovered && isEnabled ? 0.32 : 0
    }

    var depthShadowOpacity: Double {
        guard isEnabled else { return 0.04 }
        return 0.09
    }

    var depthShadowRadius: Double {
        if !isEnabled {
            return 4
        }
        return 6
    }

    var depthShadowY: Double {
        if !isEnabled {
            return 1
        }
        return 2
    }

    var borderOpacity: Double {
        guard isEnabled else { return 0.08 }
        return isHovered ? 0.28 : 0.16
    }
}

struct LauncherResultsLayoutMetrics: Equatable {
    static let standard = LauncherResultsLayoutMetrics(
        rowHorizontalInset: 16,
        rowVerticalInset: 14,
        rowSpacing: 10,
        cornerRadius: 24,
        insetBackingTintOpacity: 0.02,
        mainPanelTintOpacity: 0.04,
        scrollIndicatorsAreVisible: true,
        scrollbarVerticalInset: 14,
        topSelectionAnchorY: 0.045,
        bottomSelectionAnchorY: 0.955
    )

    let rowHorizontalInset: Double
    let rowVerticalInset: Double
    let rowSpacing: Double
    let cornerRadius: Double
    let insetBackingTintOpacity: Double
    let mainPanelTintOpacity: Double
    let scrollIndicatorsAreVisible: Bool
    let scrollbarVerticalInset: Double
    let topSelectionAnchorY: Double
    let bottomSelectionAnchorY: Double

    var rowTrailingInset: Double {
        rowHorizontalInset
    }
}

struct LauncherQueryUpdatePolicy: Equatable {
    static let standard = LauncherQueryUpdatePolicy()

    func selectedIndexAfterQueryChange(resultCount: Int) -> Int {
        0
    }

    func shouldRequestTopScrollAfterQueryChange(resultCount: Int) -> Bool {
        resultCount > 0
    }
}

struct LauncherRowActionInteractionState: Equatable {
    let isHovered: Bool
    let isActive: Bool
    let isEnabled: Bool

    var symbolOpacity: Double {
        isEnabled ? 1 : 0.48
    }

    var tintOpacity: Double {
        guard isEnabled else { return 0 }
        if isActive {
            return 0.28
        }
        if isHovered {
            return 0.16
        }
        return 0
    }

    var fillSymbolOpacity: Double {
        guard isEnabled else { return 0 }
        if isActive {
            return 0.72
        }
        if isHovered {
            return 0.32
        }
        return 0
    }

    var borderOpacity: Double {
        guard isEnabled else { return 0.08 }
        if isActive {
            return 0.38
        }
        if isHovered {
            return 0.28
        }
        return 0.16
    }

    var depthShadowOpacity: Double {
        guard isEnabled else { return 0.04 }
        return isActive ? 0.13 : 0.09
    }

    var depthShadowRadius: Double {
        guard isEnabled else { return 4 }
        return isActive ? 8 : 6
    }

    var depthShadowY: Double {
        guard isEnabled else { return 1 }
        return isActive ? 3 : 2
    }
}
