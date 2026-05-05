import AppKit
import Carbon
import CoreGraphics

func normalized(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}
func applyPreferredButtonBezelStyle(_ button: NSButton) {
    if #available(macOS 26.0, *) {
        button.bezelStyle = .glass
    } else {
        button.bezelStyle = .texturedRounded
    }
}

func primaryDisplayScreen() -> NSScreen? {
    let mainDisplayID = CGMainDisplayID()
    return NSScreen.screens.first { screen in
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return screenNumber.uint32Value == mainDisplayID
    }
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0

    if deviceFlags.contains(.control) {
        modifiers |= UInt32(controlKey)
    }
    if deviceFlags.contains(.option) {
        modifiers |= UInt32(optionKey)
    }
    if deviceFlags.contains(.shift) {
        modifiers |= UInt32(shiftKey)
    }
    if deviceFlags.contains(.command) {
        modifiers |= UInt32(cmdKey)
    }

    return modifiers
}
func carbonModifierDisplayNames(_ modifiers: UInt32) -> [String] {
    var names: [String] = []

    if modifiers & UInt32(controlKey) != 0 {
        names.append("Control")
    }
    if modifiers & UInt32(optionKey) != 0 {
        names.append("Option")
    }
    if modifiers & UInt32(shiftKey) != 0 {
        names.append("Shift")
    }
    if modifiers & UInt32(cmdKey) != 0 {
        names.append("Command")
    }

    return names
}
func displayKeyName(for keyCode: UInt32, characters: String?) -> String {
    switch Int(keyCode) {
    case kVK_Space:
        return "Space"
    case kVK_Return:
        return "Return"
    case kVK_Tab:
        return "Tab"
    case kVK_Escape:
        return "Escape"
    case kVK_Delete:
        return "Delete"
    case kVK_ForwardDelete:
        return "Forward Delete"
    case kVK_LeftArrow:
        return "Left"
    case kVK_RightArrow:
        return "Right"
    case kVK_UpArrow:
        return "Up"
    case kVK_DownArrow:
        return "Down"
    case kVK_Home:
        return "Home"
    case kVK_End:
        return "End"
    case kVK_PageUp:
        return "Page Up"
    case kVK_PageDown:
        return "Page Down"
    default:
        break
    }

    guard let characters, !characters.isEmpty else {
        return "Key \(keyCode)"
    }

    if characters == "," {
        return "Comma"
    }

    let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "Key \(keyCode)"
    }

    return trimmed.uppercased()
}
extension HotKeyConfiguration {
    init?(event: NSEvent) {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            return nil
        }

        let keyCode = UInt32(event.keyCode)
        self.init(
            keyCode: keyCode,
            modifiers: modifiers,
            keyName: displayKeyName(for: keyCode, characters: event.charactersIgnoringModifiers)
        )
    }
}
extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}

enum LauncherKeyRoutingPolicy {
    static func shouldRouteAlphaNumeric(mode: LauncherMode, fileFocusState: FileBrowserFocusState?) -> Bool {
        guard mode == .files else { return true }
        return fileFocusState != .renaming
    }

    static func shouldPassThroughFileTextEditing(
        mode: LauncherMode,
        fileFocusState: FileBrowserFocusState?,
        keyCode: UInt16,
        eventType: NSEvent.EventType
    ) -> Bool {
        guard mode == .files,
              fileFocusState == .renaming else {
            return false
        }
        guard eventType == .keyDown || eventType == .keyUp else {
            return false
        }
        return keyCode != UInt16(kVK_Return)
            && keyCode != UInt16(kVK_ANSI_KeypadEnter)
            && keyCode != UInt16(kVK_Escape)
    }
}

extension NSEvent {
    var commandNumberMode: LauncherMode? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              let charactersIgnoringModifiers,
              let number = Int(charactersIgnoringModifiers) else {
            return nil
        }
        return LauncherMode(commandNumber: number)
    }

    var firstAlphaNumericCharacter: Character? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isEmpty,
              let charactersIgnoringModifiers,
              let character = charactersIgnoringModifiers.first,
              character.isLetter || character.isNumber else {
            return nil
        }
        return character
    }

    var isCommandR: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && charactersIgnoringModifiers?.lowercased() == "r"
    }

    var isCommandComma: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && charactersIgnoringModifiers == ","
    }

    var isCommandP: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && charactersIgnoringModifiers?.lowercased() == "p"
    }

    var isCommandUpArrow: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command)
            && flags.intersection([.shift, .option, .control]).isEmpty
            && keyCode == UInt16(kVK_UpArrow)
    }

    var isCommandDownArrow: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command)
            && flags.intersection([.shift, .option, .control]).isEmpty
            && keyCode == UInt16(kVK_DownArrow)
    }

}
