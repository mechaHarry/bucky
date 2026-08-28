import SwiftUI

typealias LauncherModeTint = StoneTint

enum LauncherModeTintPolicy {
    static func tint(for mode: LauncherMode) -> LauncherModeTint {
        mode.stoneDefinition.tint
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
