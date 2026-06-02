import Foundation

struct AgendaNoteReference: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let url: URL
    let addedAt: Date

    init(id: UUID = UUID(), url: URL, addedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
    }

    var title: String {
        url.lastPathComponent
    }

    var subtitle: String {
        url.deletingLastPathComponent().path
    }

    var searchText: String {
        AgendaFilter.normalized([title, subtitle, url.path].joined(separator: " "))
    }
}

struct AgendaFile: Codable {
    var notes: [AgendaNoteReference]
}

enum AgendaNavigationDirection: Equatable {
    case up
    case down
    case left
    case right
}

struct AgendaFilter {
    static func filterNotes(_ notes: [AgendaNoteReference], query: String) -> [AgendaNoteReference] {
        let tokens = tokens(for: query)
        guard !tokens.isEmpty else { return notes }
        return notes.filter { note in
            tokens.allSatisfy { note.searchText.contains($0) }
        }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func tokens(for query: String) -> [String] {
        normalized(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}
