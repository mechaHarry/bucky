import AppKit

enum LauncherShortcutPolicy {
    static func command(for event: NSEvent, modeForNumber: (Int) -> LauncherMode?) -> LauncherCommand? {
        guard event.type == .keyDown else { return nil }
        if let number = event.commandNumber, let mode = modeForNumber(number) { return .switchMode(mode) }
        if event.isCommandR { return .reindex }
        if event.isCommandComma { return .settings }
        if event.isCommandSlash { return .help }
        if event.isCommandP { return .togglePin }
        if event.isCommandLeftBracket { return .historyBack }
        if event.isCommandRightBracket { return .historyForward }
        if event.isCommandUpArrow { return .top }
        if event.isCommandDownArrow { return .bottom }
        if event.isCommandLeftArrow { return .previousMode }
        if event.isCommandRightArrow { return .nextMode }
        return nil
    }
}
