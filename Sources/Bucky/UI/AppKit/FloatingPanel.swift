import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class FloatingPanel: NSPanel {
    var commandHandler: ((LauncherCommand) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isCommandR, commandHandler?(.reindex) == true {
            return true
        }
        if event.isCommandComma, commandHandler?(.settings) == true {
            return true
        }
        if event.isToolsShortcut, commandHandler?(.toggleToolsMode) == true {
            return true
        }
        if event.isCommandUpArrow, commandHandler?(.top) == true {
            return true
        }
        if event.isCommandDownArrow, commandHandler?(.bottom) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if commandHandler?(.close) != true {
            orderOut(sender)
        }
    }
}
