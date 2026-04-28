import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class LauncherSearchField: NSSearchField {
    var commandHandler: ((LauncherCommand) -> Bool)?

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

    override func keyDown(with event: NSEvent) {
        if event.isToolsShortcut, commandHandler?(.toggleToolsMode) == true {
            return
        }
        if event.isCommandUpArrow, commandHandler?(.top) == true {
            return
        }
        if event.isCommandDownArrow, commandHandler?(.bottom) == true {
            return
        }

        switch event.keyCode {
        case 126:
            if commandHandler?(.up) == true { return }
        case 125:
            if commandHandler?(.down) == true { return }
        case 36, 76:
            if commandHandler?(.open) == true { return }
        case 53:
            if commandHandler?(.close) == true { return }
        default:
            break
        }

        super.keyDown(with: event)
    }
}
