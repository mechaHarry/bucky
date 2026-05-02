enum LauncherHeaderButtonStyle: Equatable {
    case stockGlass
    case prominentAccentGlass
}

struct LauncherHeaderButtonStylePolicy: Equatable {
    let isActive: Bool

    var style: LauncherHeaderButtonStyle {
        isActive ? .prominentAccentGlass : .stockGlass
    }
}
