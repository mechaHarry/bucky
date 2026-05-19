import SwiftUI

struct LauncherModeTint: Equatable {
    let activeHex: Int
    let panelHex: Int
    let iconHex: Int

    init(activeHex: Int, panelHex: Int, iconHex: Int? = nil) {
        self.activeHex = activeHex
        self.panelHex = panelHex
        self.iconHex = iconHex ?? activeHex
    }
}

enum LauncherModeTintPolicy {
    static func tint(for mode: LauncherMode) -> LauncherModeTint {
        switch mode {
        case .applications:
            return LauncherModeTint(activeHex: 0x266EF6, panelHex: 0x08578A)
        case .calculator:
            return LauncherModeTint(activeHex: 0xFFD300, panelHex: 0xFFC239, iconHex: 0x3A2B00)
        case .dictionary:
            return LauncherModeTint(activeHex: 0xE429F2, panelHex: 0xBF00FF)
        case .files:
            return LauncherModeTint(activeHex: 0xFF0130, panelHex: 0xC60404)
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

    static func inactiveOrbColor(for mode: LauncherMode) -> Color {
        activeColor(for: mode).opacity(ModeSwitcherTintPolicy.inactiveOrbGlassTintOpacity)
    }

    static func inactiveOrbIconColor(for mode: LauncherMode) -> Color {
        iconColor(for: mode).opacity(ModeSwitcherTintPolicy.inactiveOrbIconOpacity)
    }

    static func panelColor(for mode: LauncherMode) -> Color {
        color(hex: tint(for: mode).panelHex)
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
