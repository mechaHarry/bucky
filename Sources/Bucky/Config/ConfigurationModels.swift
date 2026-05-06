import Carbon

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

enum LauncherAnimationTiming: String, Codable, CaseIterable, Identifiable {
    case smooth
    case snappy

    static let defaultValue: LauncherAnimationTiming = .snappy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smooth:
            return "Smooth"
        case .snappy:
            return "Snappy"
        }
    }
}

struct BuckySettings: Codable {
    var hotKey: HotKeyConfiguration
    var launchAtStartup: Bool
    var animationTiming: LauncherAnimationTiming
    var fileBrowserStartDirectory: URL?

    static let defaultValue = BuckySettings(
        hotKey: .defaultValue,
        launchAtStartup: false,
        animationTiming: .defaultValue,
        fileBrowserStartDirectory: nil
    )

    init(
        hotKey: HotKeyConfiguration,
        launchAtStartup: Bool,
        animationTiming: LauncherAnimationTiming = .defaultValue,
        fileBrowserStartDirectory: URL? = nil
    ) {
        self.hotKey = hotKey
        self.launchAtStartup = launchAtStartup
        self.animationTiming = animationTiming
        self.fileBrowserStartDirectory = fileBrowserStartDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case hotKey
        case launchAtStartup
        case animationTiming
        case fileBrowserStartDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try container.decodeIfPresent(HotKeyConfiguration.self, forKey: .hotKey) ?? .defaultValue
        launchAtStartup = try container.decodeIfPresent(Bool.self, forKey: .launchAtStartup) ?? false
        animationTiming = try container.decodeIfPresent(LauncherAnimationTiming.self, forKey: .animationTiming) ?? .defaultValue
        fileBrowserStartDirectory = try container.decodeIfPresent(URL.self, forKey: .fileBrowserStartDirectory)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotKey, forKey: .hotKey)
        try container.encode(launchAtStartup, forKey: .launchAtStartup)
        try container.encode(animationTiming, forKey: .animationTiming)
        try container.encodeIfPresent(fileBrowserStartDirectory, forKey: .fileBrowserStartDirectory)
    }
}
