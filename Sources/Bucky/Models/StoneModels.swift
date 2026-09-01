import Foundation

struct StoneID: RawRepresentable, CaseIterable, Identifiable, Hashable {
    let rawValue: Int

    static let applications = StoneID(rawValue: 1)
    static let calculator = StoneID(rawValue: 2)
    static let dictionary = StoneID(rawValue: 3)
    static let files = StoneID(rawValue: 4)
    static let allCases: [StoneID] = [.applications, .calculator, .dictionary, .files]

    var id: Self { self }
}

enum StoneSurface: Hashable {
    case textInput
    case fileBrowser

    var acceptsTextInput: Bool {
        switch self {
        case .textInput:
            return true
        case .fileBrowser:
            return false
        }
    }
}

enum StoneUpdatePolicy: Equatable, Hashable {
    case immediate
    case deferred(delayNanoseconds: UInt64)
}

struct StoneTint: Equatable, Hashable {
    let activeHex: Int
    let panelHex: Int
    let iconHex: Int
    let darkModeIconHex: Int
}

struct StonePresentation: Equatable, Hashable {
    let title: String
    let placeholder: String
    let systemImage: String
}

struct StoneDefinition: Identifiable, Equatable, Hashable {
    let id: StoneID
    let shortcutNumber: Int
    let presentation: StonePresentation
    let surface: StoneSurface
    let updatePolicy: StoneUpdatePolicy
    let tint: StoneTint

    var acceptsTextInput: Bool {
        surface.acceptsTextInput
    }
}

@MainActor
protocol StoneProvider: AnyObject {
    var definition: StoneDefinition { get }

    func snapshot(for query: String) -> StoneResultSnapshot
    func updateSnapshot(for query: String) async -> StoneResultSnapshot
    func cancel()
    func activation(for row: StoneResultRow) -> StoneActivation
    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> StoneProviderActivationResult
}

typealias TextStoneProvider = StoneProvider

enum StoneProviderActivationResult: Equatable {
    case unhandled
    case handled(shouldRefresh: Bool, resetSelection: Bool, shouldHide: Bool)
}

typealias TextStoneActivationResult = StoneProviderActivationResult

@MainActor
final class StoneProviderRegistry {
    private let providersByID: [StoneID: any StoneProvider]
    let orderedDefinitions: [StoneDefinition]

    init(providers: [any StoneProvider]) {
        var providersByID: [StoneID: any StoneProvider] = [:]
        var orderedDefinitions = StoneCatalog.orderedDefinitions

        for provider in providers {
            let previous = providersByID.updateValue(provider, forKey: provider.definition.id)
            precondition(previous == nil, "StoneProviderRegistry contains duplicate provider for \(provider.definition.id)")

            if let index = orderedDefinitions.firstIndex(where: { $0.id == provider.definition.id }) {
                orderedDefinitions[index] = provider.definition
            } else {
                orderedDefinitions.append(provider.definition)
            }
        }

        precondition(
            Set(orderedDefinitions.map(\.id)).count == orderedDefinitions.count,
            "StoneProviderRegistry contains duplicate Stone definitions"
        )
        precondition(
            Set(orderedDefinitions.map(\.shortcutNumber)).count == orderedDefinitions.count,
            "StoneProviderRegistry contains duplicate Stone shortcut numbers"
        )
        self.providersByID = providersByID
        self.orderedDefinitions = orderedDefinitions
    }

    var registeredStoneIDs: [StoneID] {
        orderedDefinitions.map(\.id).filter { providersByID[$0] != nil }
    }

    var availableModes: [LauncherMode] {
        orderedDefinitions.map(LauncherMode.init(definition:))
    }

    func mode(forShortcutNumber shortcutNumber: Int) -> LauncherMode? {
        guard let definition = orderedDefinitions.first(where: { $0.shortcutNumber == shortcutNumber }) else {
            return nil
        }
        return LauncherMode(definition: definition)
    }

    func provider(for id: StoneID) -> (any StoneProvider)? {
        providersByID[id]
    }

    func snapshot(for id: StoneID, query: String) -> StoneResultSnapshot? {
        providersByID[id]?.snapshot(for: query)
    }

    func updateSnapshot(for id: StoneID, query: String) async -> StoneResultSnapshot? {
        guard let provider = providersByID[id] else { return nil }
        return await provider.updateSnapshot(for: query)
    }

    func cancel(for id: StoneID) {
        providersByID[id]?.cancel()
    }

    func activation(for id: StoneID, row: StoneResultRow) -> StoneActivation? {
        providersByID[id]?.activation(for: row)
    }

    func perform(_ activation: StoneActivation, for id: StoneID, row: StoneResultRow) -> StoneProviderActivationResult {
        providersByID[id]?.perform(activation, for: row) ?? .unhandled
    }
}

enum StoneCatalog {
    static let orderedDefinitions: [StoneDefinition] = [
        StoneDefinition(
            id: .applications,
            shortcutNumber: 1,
            presentation: StonePresentation(
                title: "Apps",
                placeholder: "Search Apps Here",
                systemImage: "square.grid.2x2"
            ),
            surface: .textInput,
            updatePolicy: .deferred(delayNanoseconds: 40_000_000),
            tint: StoneTint(
                activeHex: 0x266EF6,
                panelHex: 0x08578A,
                iconHex: 0x0B3D91,
                darkModeIconHex: 0x9CC7FF
            )
        ),
        StoneDefinition(
            id: .calculator,
            shortcutNumber: 2,
            presentation: StonePresentation(
                title: "Calculator",
                placeholder: "Perform Calculations Here",
                systemImage: "123.rectangle.fill"
            ),
            surface: .textInput,
            updatePolicy: .immediate,
            tint: StoneTint(
                activeHex: 0xFFD300,
                panelHex: 0xFFC239,
                iconHex: 0x3A2B00,
                darkModeIconHex: 0xFFF0A3
            )
        ),
        StoneDefinition(
            id: .dictionary,
            shortcutNumber: 3,
            presentation: StonePresentation(
                title: "Dictionary",
                placeholder: "Search Dictionary Here",
                systemImage: "text.book.closed"
            ),
            surface: .textInput,
            updatePolicy: .deferred(delayNanoseconds: 80_000_000),
            tint: StoneTint(
                activeHex: 0xE429F2,
                panelHex: 0xBF00FF,
                iconHex: 0x6E1977,
                darkModeIconHex: 0xF5B8FF
            )
        ),
        StoneDefinition(
            id: .files,
            shortcutNumber: 4,
            presentation: StonePresentation(
                title: "Files",
                placeholder: "Browse Files",
                systemImage: "folder"
            ),
            surface: .fileBrowser,
            updatePolicy: .immediate,
            tint: StoneTint(
                activeHex: 0xFF0130,
                panelHex: 0xC60404,
                iconHex: 0x7A0018,
                darkModeIconHex: 0xFFA6B8
            )
        )
    ]

    private static let definitionsByID: [StoneID: StoneDefinition] = {
        var definitionsByID: [StoneID: StoneDefinition] = [:]

        for definition in orderedDefinitions {
            let previous = definitionsByID.updateValue(definition, forKey: definition.id)
            precondition(previous == nil, "StoneCatalog contains duplicate definition for \(definition.id)")
        }

        precondition(definitionsByID.count == orderedDefinitions.count, "StoneCatalog lost definitions while indexing by id")
        return definitionsByID
    }()

    private static let definitionsByShortcutNumber: [Int: StoneDefinition] = {
        var definitionsByShortcutNumber: [Int: StoneDefinition] = [:]

        for definition in orderedDefinitions {
            let previous = definitionsByShortcutNumber.updateValue(definition, forKey: definition.shortcutNumber)
            precondition(previous == nil, "StoneCatalog contains duplicate shortcut number \(definition.shortcutNumber)")
        }

        precondition(definitionsByShortcutNumber.count == orderedDefinitions.count, "StoneCatalog lost definitions while indexing by shortcut number")
        return definitionsByShortcutNumber
    }()

    static func definition(for id: StoneID) -> StoneDefinition {
        guard let definition = definitionsByID[id] else {
            preconditionFailure("StoneCatalog is missing definition for \(id)")
        }

        return definition
    }

    static func definition(forRawValue rawValue: Int) -> StoneDefinition? {
        definitionsByID[StoneID(rawValue: rawValue)]
    }

    static func definition(forShortcutNumber shortcutNumber: Int) -> StoneDefinition? {
        definitionsByShortcutNumber[shortcutNumber]
    }
}
