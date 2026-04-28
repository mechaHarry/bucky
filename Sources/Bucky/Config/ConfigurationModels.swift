import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

struct ExclusionsFile: Codable {
    var excludedPaths: [String]
}
struct InclusionsFile: Codable {
    var includedPaths: [String]
}
struct HotKeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyName: String

    static let defaultValue = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        keyName: "Space"
    )

    var displayName: String {
        let modifierNames = carbonModifierDisplayNames(modifiers)
        guard !modifierNames.isEmpty else { return keyName }
        return (modifierNames + [keyName]).joined(separator: "+")
    }
}
struct BuckySettings: Codable {
    var hotKey: HotKeyConfiguration
    var launchAtStartup: Bool

    static let defaultValue = BuckySettings(
        hotKey: .defaultValue,
        launchAtStartup: false
    )
}
