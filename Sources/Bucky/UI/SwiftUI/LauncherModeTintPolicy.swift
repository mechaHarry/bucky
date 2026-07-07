import SwiftUI

struct LauncherModeTint: Equatable {
    let activeHex: Int
    let panelHex: Int
    let iconHex: Int
    let darkModeIconHex: Int

    init(activeHex: Int, panelHex: Int, iconHex: Int? = nil, darkModeIconHex: Int? = nil) {
        self.activeHex = activeHex
        self.panelHex = panelHex
        self.iconHex = iconHex ?? activeHex
        self.darkModeIconHex = darkModeIconHex ?? iconHex ?? activeHex
    }
}

enum LauncherModeTintPolicy {
    static func appsTint(for route: ApplicationQueryRoute) -> LauncherModeTint {
        switch route {
        case .applications:
            return tint(for: .applications)
        case .calculator:
            return LauncherModeTint(activeHex: 0xFFD300, panelHex: 0xB08A00, iconHex: 0x6B5200, darkModeIconHex: 0xFFE98A)
        case .dictionary:
            return LauncherModeTint(activeHex: 0xE429F2, panelHex: 0xBF00FF, iconHex: 0x6E1977, darkModeIconHex: 0xF5B8FF)
        }
    }

    static func tint(for mode: LauncherMode) -> LauncherModeTint {
        switch mode {
        case .applications:
            return LauncherModeTint(activeHex: 0x266EF6, panelHex: 0x08578A, iconHex: 0x0B3D91, darkModeIconHex: 0x9CC7FF)
        case .files:
            return LauncherModeTint(activeHex: 0xFF0130, panelHex: 0xC60404, iconHex: 0x7A0018, darkModeIconHex: 0xFFA6B8)
        case .agenda:
            return LauncherModeTint(activeHex: 0x12E772, panelHex: 0x35B535, iconHex: 0x0D5F2F, darkModeIconHex: 0xB7FFD1)
        }
    }

    static func activeColor(for mode: LauncherMode) -> Color {
        color(hex: tint(for: mode).activeHex)
    }

    static func selectionColor(for mode: LauncherMode) -> Color {
        activeColor(for: mode)
    }

    static func iconColor(for mode: LauncherMode) -> Color {
        color(hex: tint(for: mode).iconHex)
    }

    static func iconColor(for mode: LauncherMode, colorScheme: ColorScheme) -> Color {
        let tint = tint(for: mode)
        return color(hex: colorScheme == .dark ? tint.darkModeIconHex : tint.iconHex)
    }

    static func inactiveOrbColor(for mode: LauncherMode) -> Color {
        activeColor(for: mode).opacity(ModeSwitcherTintPolicy.inactiveOrbGlassTintOpacity)
    }

    static func inactiveOrbIconColor(for mode: LauncherMode, colorScheme: ColorScheme) -> Color {
        iconColor(for: mode, colorScheme: colorScheme).opacity(ModeSwitcherTintPolicy.inactiveOrbIconOpacity)
    }

    static func panelColor(for mode: LauncherMode) -> Color {
        color(hex: tint(for: mode).panelHex)
    }

    static func activeColor(for route: ApplicationQueryRoute) -> Color {
        color(hex: appsTint(for: route).activeHex)
    }

    static func iconColor(for route: ApplicationQueryRoute, colorScheme: ColorScheme) -> Color {
        let tint = appsTint(for: route)
        return color(hex: colorScheme == .dark ? tint.darkModeIconHex : tint.iconHex)
    }

    static func panelColor(for route: ApplicationQueryRoute) -> Color {
        color(hex: appsTint(for: route).panelHex)
    }

    private static func color(hex: Int) -> Color {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

enum ModeSwitcherTintPolicy {
    static let activePillTintOpacity = 0.22
    static let inactiveOrbGlassTintOpacity = 0.34
    static let inactiveOrbIconOpacity = 0.94
}
