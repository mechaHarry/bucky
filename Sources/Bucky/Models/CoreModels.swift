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
    let inputText: String?
    let previewText: String?

    init(
        title: String,
        subtitle: String,
        copyText: String?,
        kind: Kind,
        inputText: String? = nil,
        previewText: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.copyText = copyText
        self.kind = kind
        self.inputText = inputText
        self.previewText = previewText
    }
}
struct DictionaryDefinitionPreview: Equatable {
    let term: String
    let definition: String
    let imageSearchURL: URL?

    init(
        term: String,
        definition: String,
        imageSearchURL: URL? = nil
    ) {
        self.term = term
        self.definition = definition
        self.imageSearchURL = imageSearchURL ?? Self.commonsImageSearchURL(for: term)
    }

    static func commonsImageSearchURL(for term: String) -> URL? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/index.php")
        components?.queryItems = [
            URLQueryItem(name: "search", value: "file:\(term)"),
            URLQueryItem(name: "title", value: "Special:MediaSearch"),
            URLQueryItem(name: "type", value: "image")
        ]
        return components?.url
    }
}
struct CalculatorResultFeedback: Equatable {
    let id: Int
    let result: String
}
struct DictionaryDefinitionSection: Equatable, Identifiable {
    struct Item: Equatable, Identifiable {
        enum Kind: Equatable {
            case definition
            case example
            case subdefinition
            case note
        }

        let kind: Kind
        let text: String
        let marker: String?

        init(kind: Kind, text: String, marker: String? = nil) {
            self.kind = kind
            self.text = text
            self.marker = marker
        }

        var id: String {
            "\(kind)-\(marker ?? "")-\(text)"
        }
    }

    let title: String
    let items: [Item]

    var id: String {
        "\(title)-\(items.map(\.id).joined(separator: "|"))"
    }

    func imageSearchTerm(for term: String) -> String {
        let variant = title
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " []"))
            .first(where: { !$0.isEmpty }) ?? "definition"
        return "\(term) \(variant)"
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
enum DictionaryDefinitionFormatter {
    private static let partOfSpeechTitles = [
        "verb",
        "noun",
        "adjective",
        "adverb",
        "pronoun",
        "preposition",
        "conjunction",
        "interjection",
        "determiner"
    ]
    private static let namedSectionTitles = ["PHRASAL VERBS", "ORIGIN"]

    static func sections(from definition: String, term: String? = nil) -> [DictionaryDefinitionSection] {
        let compactDefinition = normalizedWhitespace(stripTermPrefix(from: definition, term: term))
        guard !compactDefinition.isEmpty else { return [] }

        let headingMatches = headingRanges(in: compactDefinition)
        guard !headingMatches.isEmpty else {
            return fallbackSections(from: compactDefinition)
        }

        return headingMatches.enumerated().compactMap { index, heading in
            let bodyStart = heading.range.upperBound
            let bodyEnd = index + 1 < headingMatches.count ? headingMatches[index + 1].range.lowerBound : compactDefinition.endIndex
            let body = String(compactDefinition[bodyStart..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            let items = items(for: body, sectionTitle: heading.title)
            guard !items.isEmpty else { return nil }
            return DictionaryDefinitionSection(title: heading.title, items: items)
        }
    }

    private static func stripTermPrefix(from definition: String, term: String?) -> String {
        guard let term,
              !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return definition
        }

        var text = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: term, options: [.caseInsensitive, .anchored]) != nil else {
            return text
        }

        text = String(text.dropFirst(term.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("|") else { return text }

        text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        if let secondPipe = text.firstIndex(of: "|") {
            text = String(text[text.index(after: secondPipe)...])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct HeadingMatch {
        let title: String
        let range: Range<String.Index>
    }

    private static func headingRanges(in text: String) -> [HeadingMatch] {
        var matches: [HeadingMatch] = []
        let nsText = text as NSString
        let pattern = "(?i)(?:^|\\s)(PHRASAL VERBS|ORIGIN|(?:verb|noun|adjective|adverb|pronoun|preposition|conjunction|interjection|determiner)(?:\\s+\\[[^\\]]+\\])?)(?=\\s+(?:\\d|[A-Za-z]))"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        for result in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else {
                continue
            }

            let rawTitle = String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = namedSectionTitles.first(where: { $0.caseInsensitiveCompare(rawTitle) == .orderedSame }) ?? rawTitle.lowercased()
            guard isKnownHeading(title) else { continue }
            matches.append(HeadingMatch(title: title, range: matchRange))
        }

        return matches
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .filter { match in
                !matches.contains { other in
                    other.range != match.range &&
                        other.range.lowerBound <= match.range.lowerBound &&
                        other.range.upperBound >= match.range.upperBound
                }
            }
    }

    private static func isKnownHeading(_ title: String) -> Bool {
        if namedSectionTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
            return true
        }
        return partOfSpeechTitles.contains { title.lowercased().hasPrefix($0) }
    }

    private static func items(for body: String, sectionTitle: String) -> [DictionaryDefinitionSection.Item] {
        if sectionTitle.caseInsensitiveCompare("ORIGIN") == .orderedSame {
            return [DictionaryDefinitionSection.Item(kind: .note, text: cleanDefinitionLine(body))]
        }

        if sectionTitle.caseInsensitiveCompare("PHRASAL VERBS") == .orderedSame {
            return definitionItems(from: body, marker: nil, firstKind: .definition)
        }

        return numberedDefinitionItems(from: body)
    }

    private static func numberedDefinitionItems(from body: String) -> [DictionaryDefinitionSection.Item] {
        let normalizedBody = normalizedWhitespace(body)
        guard !normalizedBody.isEmpty else { return [] }
        let nsBody = normalizedBody as NSString
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)(\\d+)\\s+") else {
            return definitionItems(from: normalizedBody, marker: nil, firstKind: .definition)
        }

        let matches = regex.matches(in: normalizedBody, range: NSRange(location: 0, length: nsBody.length))
        guard !matches.isEmpty else {
            return definitionItems(from: normalizedBody, marker: nil, firstKind: .definition)
        }

        var items: [DictionaryDefinitionSection.Item] = []
        for (index, match) in matches.enumerated() {
            guard let markerRange = Range(match.range(at: 1), in: normalizedBody) else { continue }
            let segmentStart = match.range.upperBound
            let segmentEnd = index + 1 < matches.count ? matches[index + 1].range.location : nsBody.length
            guard segmentStart <= segmentEnd,
                  let bodyRange = Range(NSRange(location: segmentStart, length: segmentEnd - segmentStart), in: normalizedBody) else {
                continue
            }

            items.append(contentsOf: definitionItems(
                from: String(normalizedBody[bodyRange]),
                marker: String(normalizedBody[markerRange]),
                firstKind: .definition
            ))
        }
        return items
    }

    private static func definitionItems(
        from text: String,
        marker: String?,
        firstKind: DictionaryDefinitionSection.Item.Kind
    ) -> [DictionaryDefinitionSection.Item] {
        let clauses = normalizedWhitespace(text)
            .components(separatedBy: " • ")
            .map(cleanDefinitionLine)
            .filter { !$0.isEmpty }

        return clauses.enumerated().flatMap { index, clause -> [DictionaryDefinitionSection.Item] in
            let kind: DictionaryDefinitionSection.Item.Kind = index == 0 ? firstKind : .subdefinition
            return splitDefinitionAndExamples(from: clause, marker: index == 0 ? marker : nil, kind: kind)
        }
    }

    private static func splitDefinitionAndExamples(
        from clause: String,
        marker: String?,
        kind: DictionaryDefinitionSection.Item.Kind
    ) -> [DictionaryDefinitionSection.Item] {
        if let example = strippedExamplePrefix(from: clause) {
            return exampleItems(from: example)
        }

        if let exampleRange = clause.range(of: "\\bExamples?:\\s*", options: [.caseInsensitive, .regularExpression]) {
            let definitionText = cleanDefinitionLine(String(clause[..<exampleRange.lowerBound]))
            let exampleText = cleanDefinitionLine(String(clause[exampleRange.upperBound...]))
            var items: [DictionaryDefinitionSection.Item] = []
            if !definitionText.isEmpty {
                items.append(DictionaryDefinitionSection.Item(kind: kind, text: definitionText, marker: marker))
            }
            items.append(contentsOf: exampleItems(from: exampleText))
            return items
        }

        guard let colonIndex = clause.firstIndex(of: ":") else {
            return [DictionaryDefinitionSection.Item(kind: kind, text: cleanDefinitionLine(clause), marker: marker)]
        }

        let definitionText = cleanDefinitionLine(String(clause[...colonIndex]))
        let exampleText = cleanDefinitionLine(String(clause[clause.index(after: colonIndex)...]))
        var items = [DictionaryDefinitionSection.Item(kind: kind, text: definitionText, marker: marker)]
        if !exampleText.isEmpty {
            items.append(contentsOf: exampleItems(from: exampleText))
        }
        return items
    }

    private static func exampleItems(from text: String) -> [DictionaryDefinitionSection.Item] {
        let cleanedText = cleanDefinitionLine(text)
        guard !cleanedText.isEmpty else { return [] }

        var examples: [String] = []
        if let firstQuote = cleanedText.firstIndex(of: "\"") {
            let leadingExample = cleanDefinitionLine(String(cleanedText[..<firstQuote]))
            if !leadingExample.isEmpty {
                examples.append(leadingExample)
            }

            let quotedText = String(cleanedText[firstQuote...])
            if let regex = try? NSRegularExpression(pattern: #""([^"]+)""#) {
                let nsQuotedText = quotedText as NSString
                for match in regex.matches(in: quotedText, range: NSRange(location: 0, length: nsQuotedText.length)) {
                    guard match.numberOfRanges > 1,
                          let range = Range(match.range(at: 1), in: quotedText) else {
                        continue
                    }
                    let example = cleanDefinitionLine(String(quotedText[range]))
                    if !example.isEmpty {
                        examples.append(example)
                    }
                }
            }
        }

        if examples.isEmpty {
            examples.append(cleanedText)
        }

        return examples.map { DictionaryDefinitionSection.Item(kind: .example, text: $0) }
    }

    private static func fallbackSections(from definition: String) -> [DictionaryDefinitionSection] {
        let lines = definition
            .split(whereSeparator: \.isNewline)
            .map { cleanDefinitionLine(String($0)) }
            .filter { !$0.isEmpty }

        let items = lines.flatMap { splitDefinitionAndExamples(from: $0, marker: nil, kind: .definition) }
        return items.isEmpty ? [] : [DictionaryDefinitionSection(title: "Definition", items: items)]
    }

    private static func strippedExamplePrefix(from line: String) -> String? {
        let prefixes = ["Example:", "Examples:"]
        for prefix in prefixes where line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
            return cleanDefinitionLine(String(line.dropFirst(prefix.count)))
        }

        if line.hasPrefix("\""), line.hasSuffix("\""), line.count > 1 {
            return String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func cleanDefinitionLine(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "•-– "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "•", with: " • ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    case files = 4
    case agenda = 5

    static let ordered: [LauncherMode] = [.applications, .files, .agenda]

    init?(commandNumber: Int) {
        self.init(rawValue: commandNumber)
    }

    var previousMode: LauncherMode {
        adjacentMode(offset: -1)
    }

    var nextMode: LauncherMode {
        adjacentMode(offset: 1)
    }

    var placeholder: String {
        switch self {
        case .applications:
            return "Search Apps Here"
        case .files:
            return "Browse Files"
        case .agenda:
            return "Agenda Scratchpad"
        }
    }

    var acceptsTextInput: Bool {
        self != .files
    }

    var shortTitle: String {
        switch self {
        case .applications:
            return "Apps"
        case .files:
            return "Files"
        case .agenda:
            return "Agenda"
        }
    }

    var helpSystemImage: String {
        switch self {
        case .applications:
            return "square.grid.2x2"
        case .files:
            return "folder"
        case .agenda:
            return "checklist"
        }
    }

    private func adjacentMode(offset: Int) -> LauncherMode {
        guard let index = Self.ordered.firstIndex(of: self) else { return self }
        let count = Self.ordered.count
        let nextIndex = (index + offset + count) % count
        return Self.ordered[nextIndex]
    }
}
