import Foundation

enum StoneResultSnapshot: Equatable {
    case loading(message: String)
    case empty(message: String)
    case message(StoneResultRow)
    case loaded(rows: [StoneResultRow])

    var rows: [StoneResultRow] {
        switch self {
        case .loading, .empty:
            return []
        case let .message(row):
            return [row]
        case let .loaded(rows):
            return rows
        }
    }

    var surfaceMessage: String? {
        switch self {
        case let .loading(message), let .empty(message):
            return message
        case .message, .loaded:
            return nil
        }
    }

    var identity: String {
        switch self {
        case let .loading(message):
            return "loading:\(message)"
        case let .empty(message):
            return "empty:\(message)"
        case let .message(row):
            return "message:\(row.identityKey)"
        case let .loaded(rows):
            return rows.map(\.identityKey).joined(separator: "\u{1F}")
        }
    }
}

struct StoneResultRow: Identifiable, Equatable, Hashable {
    enum ID: Equatable, Hashable {
        case application(AppRowID)
        case tool(kind: Kind, key: String)
        case file(URL)

        var identityKey: String {
            switch self {
            case let .application(id):
                return "application:\(id.rawValue)"
            case let .tool(kind, key):
                return "tool:\(kind.rawValue):\(key)"
            case let .file(url):
                return "file:\(url.standardizedFileURL.path)"
            }
        }
    }

    enum Kind: String, Equatable, Hashable {
        case application
        case calculation
        case calculationHistory
        case dictionary
        case dictionaryHistory
        case message
        case file
    }

    let id: ID
    let display: String
    let subtitle: String
    let copyText: String?
    let kind: Kind
    let primaryActivation: StoneActivation
    let accessoryActivation: StoneActivation
    let iconURL: URL?
    let accessoryText: String?

    init(
        id: ID,
        display: String,
        subtitle: String,
        copyText: String?,
        kind: Kind,
        primaryActivation: StoneActivation,
        accessoryActivation: StoneActivation,
        iconURL: URL? = nil,
        accessoryText: String? = nil
    ) {
        self.id = id
        self.display = display
        self.subtitle = subtitle
        self.copyText = copyText
        self.kind = kind
        self.primaryActivation = primaryActivation
        self.accessoryActivation = accessoryActivation
        self.iconURL = iconURL
        self.accessoryText = accessoryText
    }

    var identityKey: String {
        [
            id.identityKey,
            display,
            subtitle,
            copyText ?? "",
            kind.rawValue,
            accessoryText ?? ""
        ].joined(separator: "\u{1E}")
    }

    static func application(id: AppRowID, item: LaunchItem) -> StoneResultRow {
        StoneResultRow(
            id: .application(id),
            display: item.title,
            subtitle: item.subtitle,
            copyText: nil,
            kind: .application,
            primaryActivation: .open(item.launchTarget),
            accessoryActivation: .none,
            iconURL: item.url,
            accessoryText: item.category.title
        )
    }

    static func tool(_ item: ToolItem) -> StoneResultRow {
        let kind = StoneResultRow.Kind(toolKind: item.kind)
        let primaryActivation = Self.primaryActivation(for: item, rowKind: kind)
        let accessoryActivation = Self.accessoryActivation(for: item, rowKind: kind, primaryActivation: primaryActivation)

        return StoneResultRow(
            id: item.stoneResultID,
            display: item.title,
            subtitle: item.subtitle,
            copyText: item.copyText,
            kind: kind,
            primaryActivation: primaryActivation,
            accessoryActivation: accessoryActivation
        )
    }

    static func file(_ entry: FileBrowserEntry) -> StoneResultRow {
        StoneResultRow(
            id: .file(entry.url),
            display: entry.name,
            subtitle: entry.url.path,
            copyText: entry.url.path,
            kind: .file,
            primaryActivation: .none,
            accessoryActivation: .none,
            iconURL: entry.url
        )
    }

    private static func primaryActivation(for item: ToolItem, rowKind: Kind) -> StoneActivation {
        switch rowKind {
        case .calculation, .calculationHistory:
            guard let copyText = item.copyText else { return .none }
            return .copy(copyText)
        case .dictionary, .dictionaryHistory:
            return dictionaryActivation(for: item.title)
        case .application, .file, .message:
            return .none
        }
    }

    private static func accessoryActivation(
        for item: ToolItem,
        rowKind: Kind,
        primaryActivation: StoneActivation
    ) -> StoneActivation {
        switch rowKind {
        case .calculation, .calculationHistory, .dictionary:
            return primaryActivation
        case .dictionaryHistory:
            return .removeHistory(item.stoneResultID)
        case .application, .file, .message:
            return .none
        }
    }

    private static func dictionaryActivation(for term: String) -> StoneActivation {
        guard let escapedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://\(escapedTerm)") else {
            return .none
        }

        return .open(.url(url))
    }
}

enum StoneActivation: Equatable, Hashable {
    case copy(String)
    case open(LaunchTarget)
    case removeHistory(StoneResultRow.ID)
    case none
}

struct StoneResultRequestGate: Equatable {
    struct Token: Equatable {
        let generation: Int
        let query: String
    }

    private(set) var generation = 0

    mutating func begin(query: String) -> Token {
        generation += 1
        return Token(generation: generation, query: query)
    }

    mutating func cancel() {
        generation += 1
    }

    func accepts(_ token: Token, currentQuery: String) -> Bool {
        generation == token.generation && currentQuery == token.query
    }
}

private extension StoneResultRow.Kind {
    init(toolKind: ToolItem.Kind) {
        switch toolKind {
        case .calculation:
            self = .calculation
        case .calculationHistory:
            self = .calculationHistory
        case .dictionary:
            self = .dictionary
        case .dictionaryHistory:
            self = .dictionaryHistory
        case .message:
            self = .message
        }
    }
}
