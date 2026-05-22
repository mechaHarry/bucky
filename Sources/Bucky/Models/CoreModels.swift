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
    case agenda = 5

    static let ordered: [LauncherMode] = [.applications, .calculator, .dictionary, .files, .agenda]

    init?(commandNumber: Int) {
        self.init(rawValue: commandNumber)
    }

    var placeholder: String {
        switch self {
        case .applications:
            return "Search Apps Here"
        case .calculator:
            return "Perform Calculations Here"
        case .dictionary:
            return "Search Dictionary Here"
        case .files:
            return "Browse Files"
        case .agenda:
            return "Agenda Scratchpad"
        }
    }

    var acceptsTextInput: Bool {
        self != .files
    }
}
