import Foundation

struct LaunchItem: Hashable {
    let title: String
    let subtitle: String
    let url: URL
    let searchText: String
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

    static let ordered: [LauncherMode] = [.applications, .calculator, .dictionary, .files]

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
        }
    }

    var acceptsTextInput: Bool {
        self != .files
    }
}
