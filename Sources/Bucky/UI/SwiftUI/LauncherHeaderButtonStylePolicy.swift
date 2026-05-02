struct LauncherHeaderButtonStylePolicy: Equatable {
    let isActive: Bool

    var usesAccentGlassTint: Bool {
        isActive
    }
}
