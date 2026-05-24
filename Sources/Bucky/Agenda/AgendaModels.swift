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

struct AgendaReminder: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var date: String
    var time: String
    var urlString: String
    var details: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        date: String = "",
        time: String = "",
        urlString: String = "",
        details: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.time = time
        self.urlString = urlString
        self.details = details
        self.createdAt = createdAt
    }

    var subtitle: String {
        let schedule = [date, time].filter { !$0.isEmpty }.joined(separator: " ")
        if !schedule.isEmpty {
            return schedule
        }
        if !urlString.isEmpty {
            return urlString
        }
        return details
    }

    var metadataLines: [String] {
        [date, time, urlString, details].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var searchText: String {
        AgendaFilter.normalized([name, date, time, urlString, details].joined(separator: " "))
    }

    var notificationDateComponents: DateComponents? {
        guard let dateComponents = AgendaReminderDateParser.dateComponents(from: date) else { return nil }
        var components = dateComponents
        if let timeComponents = AgendaReminderDateParser.timeComponents(from: time) {
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
        } else {
            components.hour = 9
            components.minute = 0
        }
        return components
    }
}

struct AgendaFile: Codable {
    var notes: [AgendaNoteReference]
    var reminders: [AgendaReminder]
}

enum AgendaReminderDateParser {
    static func dateComponents(from value: String) -> DateComponents? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(calendar: calendar, year: parts[0], month: parts[1], day: parts[2])
    }

    static func timeComponents(from value: String) -> DateComponents? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return DateComponents(calendar: calendar, hour: parts[0], minute: parts[1])
    }

    private static var calendar: Calendar {
        Calendar(identifier: .gregorian)
    }
}

enum AgendaSelectionColumn: String, Codable, Equatable {
    case notes
    case reminders
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

    static func filterReminders(_ reminders: [AgendaReminder], query: String) -> [AgendaReminder] {
        let tokens = tokens(for: query)
        guard !tokens.isEmpty else { return reminders }
        return reminders.filter { reminder in
            tokens.allSatisfy { reminder.searchText.contains($0) }
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
