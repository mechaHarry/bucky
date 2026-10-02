import Carbon

struct ExclusionsFile: Codable {
    var excludedPaths: [String]
    var excludedIdentities: [ExclusionIdentity] = []

    init(excludedPaths: [String], excludedIdentities: [ExclusionIdentity] = []) {
        self.excludedPaths = excludedPaths
        self.excludedIdentities = excludedIdentities
    }
    private enum CodingKeys: String, CodingKey { case excludedPaths, excludedIdentities }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        excludedPaths = try container.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        excludedIdentities = try container.decodeIfPresent([ExclusionIdentity].self, forKey: .excludedIdentities) ?? []
    }
}

struct ExclusionIdentity: Codable, Hashable {
    enum Kind: String, Codable { case application, url, customAction }
    let kind: Kind
    let value: String

    init(item: LaunchItem) {
        switch item.launchTarget {
        case let .application(url):
            kind = .application
            value = url.standardizedFileURL.path
        case let .url(url):
            kind = .url
            value = url.absoluteString
        case .shellCommand:
            kind = .customAction
            value = item.url.absoluteString
        }
    }
    init?(selectionKey: String) {
        let components = selectionKey.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "identity",
              let kind = Kind(rawValue: String(components[1])),
              let data = Data(base64Encoded: String(components[2])),
              let value = String(data: data, encoding: .utf8) else { return nil }
        self.kind = kind
        self.value = value
    }
    // Reversible selection keys let Settings remove typed exclusions without migrating legacy data.
    var selectionKey: String {
        "identity:\(kind.rawValue):\(Data(value.utf8).base64EncodedString())"
    }
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

struct CustomAction: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var command: String

    init(id: UUID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}

struct BuckySettings: Codable {
    var hotKey: HotKeyConfiguration
    var launchAtStartup: Bool
    var animationTiming: LauncherAnimationTiming
    var fileBrowserStartDirectory: URL?
    var customActions: [CustomAction]

    static let defaultValue = BuckySettings(
        hotKey: .defaultValue,
        launchAtStartup: false,
        animationTiming: .defaultValue,
        fileBrowserStartDirectory: nil,
        customActions: []
    )

    init(
        hotKey: HotKeyConfiguration,
        launchAtStartup: Bool,
        animationTiming: LauncherAnimationTiming = .defaultValue,
        fileBrowserStartDirectory: URL? = nil,
        customActions: [CustomAction] = []
    ) {
        self.hotKey = hotKey
        self.launchAtStartup = launchAtStartup
        self.animationTiming = animationTiming
        self.fileBrowserStartDirectory = fileBrowserStartDirectory
        self.customActions = customActions
    }

    private enum CodingKeys: String, CodingKey {
        case hotKey
        case launchAtStartup
        case animationTiming
        case fileBrowserStartDirectory
        case customActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try container.decodeIfPresent(HotKeyConfiguration.self, forKey: .hotKey) ?? .defaultValue
        launchAtStartup = try container.decodeIfPresent(Bool.self, forKey: .launchAtStartup) ?? false
        animationTiming = try container.decodeIfPresent(LauncherAnimationTiming.self, forKey: .animationTiming) ?? .defaultValue
        fileBrowserStartDirectory = try container.decodeIfPresent(URL.self, forKey: .fileBrowserStartDirectory)
        customActions = try container.decodeIfPresent([CustomAction].self, forKey: .customActions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotKey, forKey: .hotKey)
        try container.encode(launchAtStartup, forKey: .launchAtStartup)
        try container.encode(animationTiming, forKey: .animationTiming)
        try container.encodeIfPresent(fileBrowserStartDirectory, forKey: .fileBrowserStartDirectory)
        try container.encode(customActions, forKey: .customActions)
    }
}
