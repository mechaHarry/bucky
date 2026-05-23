enum LauncherCommand {
    case up
    case down
    case left
    case right
    case top
    case bottom
    case open
    case close
    case reindex
    case settings
    case switchMode(LauncherMode)
    case previousMode
    case nextMode
    case clearHistory
    case togglePin
    case prepareSpaceInteraction
    case space
    case shiftSpace
    case beginSpaceHold
    case endSpaceHold
    case alphaNumeric(Character)
    case shiftAlphaNumeric(Character)
    case beginPinnedFocus
    case endPinnedFocus
    case historyBack
    case historyForward
}
