import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

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
struct DictionaryResult: Hashable {
    let term: String
    let definition: String
}
enum LauncherMode {
    case applications
    case tools
}
