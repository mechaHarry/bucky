import Foundation

enum LaunchTarget: Hashable {
    case application(URL)
    case url(URL)
    case shellCommand(String)
}
enum LaunchItemCategory: String, Codable, Hashable {
    case app
    case settings
    case action

    var title: String {
        switch self {
        case .app:
            return "App"
        case .settings:
            return "Settings"
        case .action:
            return "Action"
        }
    }
}
struct LaunchItem: Hashable {
    let title: String
    let subtitle: String
    let url: URL
    let launchTarget: LaunchTarget
    let category: LaunchItemCategory
    let searchText: String

    init(
        title: String,
        subtitle: String,
        url: URL,
        launchTarget: LaunchTarget? = nil,
        category: LaunchItemCategory = .app,
        searchText: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.launchTarget = launchTarget ?? .application(url)
        self.category = category
        self.searchText = searchText
    }
}
struct ToolItem: Hashable {
    enum Kind: Hashable {
        case calculation
        case calculationHistory
        case dictionary
        case dictionaryHistory
        case message
    }

    let title: String
    let subtitle: String
    let copyText: String?
    let kind: Kind
    let stoneResultID: StoneResultRow.ID

    init(
        title: String,
        subtitle: String,
        copyText: String?,
        kind: Kind,
        stoneResultID: StoneResultRow.ID? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.copyText = copyText
        self.kind = kind
        self.stoneResultID = stoneResultID ?? Self.defaultStoneResultID(
            title: title,
            subtitle: subtitle,
            copyText: copyText,
            kind: kind
        )
    }

    private static func defaultStoneResultID(
        title: String,
        subtitle: String,
        copyText: String?,
        kind: Kind
    ) -> StoneResultRow.ID {
        switch kind {
        case .calculation:
            return .tool(kind: .calculation, key: "live:\(subtitle)")
        case .calculationHistory:
            return .tool(kind: .calculationHistory, key: "history:\(title)")
        case .dictionary:
            return .tool(kind: .dictionary, key: "term:\(normalized(title))")
        case .dictionaryHistory:
            return .tool(kind: .dictionaryHistory, key: "history:\(normalized(title))")
        case .message:
            return .tool(kind: .message, key: "message:\(title):\(subtitle):\(copyText ?? "")")
        }
    }
}
struct CalculationHistoryEntry: Codable, Hashable {
    let expression: String
    let result: String
    let date: Date
}
struct CalculationHistoryFile: Codable {
    var calculations: [CalculationHistoryEntry]
}
struct DictionaryHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let term: String
    let date: Date

    init(id: UUID = UUID(), term: String, date: Date) {
        self.id = id
        self.term = term
        self.date = date
    }
}
struct DictionaryHistoryFile: Codable {
    var words: [DictionaryHistoryEntry]
}
struct DictionaryResult: Hashable {
    let term: String
    let definition: String
}
enum LauncherMode: Int, CaseIterable {
    case applications = 1
    case calculator = 2
    case dictionary = 3
    case files = 4

    static let ordered: [LauncherMode] = StoneCatalog.orderedDefinitions.map { LauncherMode(stoneID: $0.id) }

    init?(commandNumber: Int) {
        guard let definition = StoneCatalog.definition(forShortcutNumber: commandNumber) else {
            return nil
        }

        self = LauncherMode(stoneID: definition.id)
    }

    init(stoneID: StoneID) {
        switch stoneID {
        case .applications:
            self = .applications
        case .calculator:
            self = .calculator
        case .dictionary:
            self = .dictionary
        case .files:
            self = .files
        }
    }

    var previousMode: LauncherMode {
        adjacentMode(offset: -1)
    }

    var nextMode: LauncherMode {
        adjacentMode(offset: 1)
    }

    var placeholder: String {
        stoneDefinition.presentation.placeholder
    }

    var acceptsTextInput: Bool {
        stoneDefinition.acceptsTextInput
    }

    var shortTitle: String {
        stoneDefinition.presentation.title
    }

    var helpSystemImage: String {
        stoneDefinition.presentation.systemImage
    }

    var shortcutNumber: Int {
        stoneDefinition.shortcutNumber
    }

    var shortcutDisplayText: String {
        "Command+\(shortcutNumber)"
    }

    var stoneID: StoneID {
        switch self {
        case .applications:
            return .applications
        case .calculator:
            return .calculator
        case .dictionary:
            return .dictionary
        case .files:
            return .files
        }
    }

    var stoneDefinition: StoneDefinition {
        StoneCatalog.definition(for: stoneID)
    }

    private func adjacentMode(offset: Int) -> LauncherMode {
        guard let index = Self.ordered.firstIndex(of: self) else { return self }
        let count = Self.ordered.count
        let nextIndex = (index + offset + count) % count
        return Self.ordered[nextIndex]
    }
}
