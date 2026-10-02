import AppKit
import XCTest
@testable import Bucky

@MainActor
final class ApplicationMenuTests: XCTestCase {
    func testNativeEditingCommandsUseTheResponderChain() throws {
        let mainMenu = ApplicationMenu.makeMainMenu()
        let editMenu = try XCTUnwrap(mainMenu.item(withTitle: "Edit")?.submenu)
        XCTAssertTrue(editMenu.autoenablesItems)
        XCTAssertEqual(editMenu.items.map(\.title), ["Cut", "Copy", "Paste", "", "Select All"])
        XCTAssertTrue(editMenu.items[3].isSeparatorItem)

        let commands: [(String, Selector, String)] = [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ]
        for (title, action, key) in commands {
            let item = try XCTUnwrap(editMenu.item(withTitle: title))
            XCTAssertEqual(item.action, action)
            XCTAssertEqual(item.keyEquivalent, key)
            XCTAssertEqual(item.keyEquivalentModifierMask, .command)
            XCTAssertNil(item.target, "Editing must follow focus, not target a particular Stone or field")
        }
    }

    func testApplicationMenuKeepsTheNativeQuitCommand() throws {
        let mainMenu = ApplicationMenu.makeMainMenu()
        let appMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
        let quit = try XCTUnwrap(appMenu.item(withTitle: "Quit Bucky"))
        XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
        XCTAssertEqual(quit.keyEquivalent, "q")
        XCTAssertNil(quit.target)
    }

    func testClipboardCommandsPassThroughInEveryExistingTextInputMode() {
        for mode in [LauncherMode.applications, .calculator, .dictionary, .files] {
            for key in ["x", "c", "v", "a"] {
                XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
                    mode: mode,
                    fileFocusState: mode == .files ? .renaming : nil,
                    charactersIgnoringModifiers: key,
                    modifierFlags: .command,
                    eventType: .keyDown
                ), "\(mode): Command+\(key) should reach the native editor")
            }
        }
    }
}
