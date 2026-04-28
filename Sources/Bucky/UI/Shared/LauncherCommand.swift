import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

enum LauncherCommand {
    case up
    case down
    case top
    case bottom
    case open
    case close
    case reindex
    case settings
    case toggleToolsMode
    case clearHistory
    case togglePin
}
