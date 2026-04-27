import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

private struct LaunchItem: Hashable {
    let title: String
    let subtitle: String
    let url: URL
    let searchText: String
}

private struct ToolItem: Hashable {
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

private struct CalculationHistoryEntry: Codable, Hashable {
    let expression: String
    let result: String
    let date: Date
}

private struct CalculationHistoryFile: Codable {
    var calculations: [CalculationHistoryEntry]
}

private struct DictionaryResult: Hashable {
    let term: String
    let definition: String
}

private enum LauncherMode {
    case applications
    case tools
}

private enum BuckyPaths {
    static var appSupportDirectory: URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportDirectory.appendingPathComponent("Bucky", isDirectory: true)
    }
}

private final class ApplicationIndexer {
    private let fileManager = FileManager.default
    private let roots = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
    ]

    func load(includedPaths: Set<String>) -> [LaunchItem] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .localizedNameKey
        ]

        var items: [LaunchItem] = []
        var seenPaths = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { url, error in
                    NSLog("Bucky index skipped %@: %@", url.path, error.localizedDescription)
                    return true
                }
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                let extensionName = url.pathExtension.lowercased()

                if extensionName == "app" {
                    if seenPaths.insert(url.path).inserted, let item = applicationItem(for: url) {
                        items.append(item)
                    }
                    enumerator.skipDescendants()
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                    continue
                }

                if values.isDirectory == true {
                    continue
                }
            }
        }

        for path in includedPaths.sorted() {
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.lowercased() == "app",
                  fileManager.fileExists(atPath: url.path),
                  seenPaths.insert(url.path).inserted,
                  let item = applicationItem(for: url) else {
                continue
            }
            items.append(item)
        }

        return items.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func applicationItem(for url: URL) -> LaunchItem? {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let title = nonEmpty(displayName)
            ?? nonEmpty(bundleName)
            ?? url.deletingPathExtension().lastPathComponent

        return LaunchItem(
            title: title,
            subtitle: url.path,
            url: url,
            searchText: normalized(title)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct ExclusionsFile: Codable {
    var excludedPaths: [String]
}

private struct InclusionsFile: Codable {
    var includedPaths: [String]
}

private struct HotKeyConfiguration: Codable, Equatable {
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

private struct BuckySettings: Codable {
    var hotKey: HotKeyConfiguration
    var launchAtStartup: Bool

    static let defaultValue = BuckySettings(
        hotKey: .defaultValue,
        launchAtStartup: false
    )
}

private final class SettingsStore {
    private let fileManager = FileManager.default
    private(set) var settings: BuckySettings
    let fileURL: URL

    init() {
        fileURL = BuckyPaths.appSupportDirectory.appendingPathComponent("settings.json")
        settings = .defaultValue
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            settings = .defaultValue
            return
        }

        do {
            settings = try JSONDecoder().decode(BuckySettings.self, from: data)
        } catch {
            NSLog("Bucky could not read settings at %@: %@", fileURL.path, error.localizedDescription)
            settings = .defaultValue
        }
    }

    func updateHotKey(_ hotKey: HotKeyConfiguration) {
        settings.hotKey = hotKey
        save()
    }

    func updateLaunchAtStartup(_ enabled: Bool) {
        settings.launchAtStartup = enabled
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save settings at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

private final class ExclusionStore {
    private let fileManager = FileManager.default
    private(set) var excludedPaths = Set<String>()
    let fileURL: URL

    init() {
        fileURL = BuckyPaths.appSupportDirectory
            .appendingPathComponent("exclusions.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            excludedPaths = []
            return
        }

        do {
            let file = try JSONDecoder().decode(ExclusionsFile.self, from: data)
            excludedPaths = Set(file.excludedPaths)
        } catch {
            NSLog("Bucky could not read exclusions at %@: %@", fileURL.path, error.localizedDescription)
            excludedPaths = []
        }
    }

    func isExcluded(_ item: LaunchItem) -> Bool {
        excludedPaths.contains(item.url.path)
    }

    func exclude(_ item: LaunchItem) {
        excludedPaths.insert(item.url.path)
        save()
    }

    func remove(path: String) {
        excludedPaths.remove(path)
        save()
    }

    func sortedPaths() -> [String] {
        excludedPaths.sorted()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let file = ExclusionsFile(excludedPaths: excludedPaths.sorted())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save exclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

private final class InclusionStore {
    private let fileManager = FileManager.default
    private(set) var includedPaths = Set<String>()
    let fileURL: URL

    private static let defaultIncludedPaths: Set<String> = [
        "/System/Library/CoreServices/Finder.app"
    ]

    init() {
        fileURL = BuckyPaths.appSupportDirectory
            .appendingPathComponent("inclusions.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            includedPaths = Self.defaultIncludedPaths
            save()
            return
        }

        do {
            let file = try JSONDecoder().decode(InclusionsFile.self, from: data)
            includedPaths = Set(file.includedPaths)
        } catch {
            NSLog("Bucky could not read inclusions at %@: %@", fileURL.path, error.localizedDescription)
            includedPaths = Self.defaultIncludedPaths
            save()
        }
    }

    func add(path: String) {
        includedPaths.insert(path)
        save()
    }

    func remove(path: String) {
        includedPaths.remove(path)
        save()
    }

    func sortedPaths() -> [String] {
        includedPaths.sorted()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let file = InclusionsFile(includedPaths: includedPaths.sorted())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save inclusions at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

private final class CalculationHistoryStore {
    private let fileManager = FileManager.default
    private(set) var calculations: [CalculationHistoryEntry] = []
    let fileURL: URL

    init() {
        fileURL = BuckyPaths.appSupportDirectory
            .appendingPathComponent("calculations.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            calculations = []
            return
        }

        do {
            let file = try JSONDecoder().decode(CalculationHistoryFile.self, from: data)
            calculations = file.calculations
        } catch {
            NSLog("Bucky could not read calculation history at %@: %@", fileURL.path, error.localizedDescription)
            calculations = []
        }
    }

    func add(expression: String, result: String) {
        let trimmedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExpression.isEmpty else { return }

        calculations.removeAll { entry in
            entry.expression == trimmedExpression && entry.result == result
        }
        calculations.insert(
            CalculationHistoryEntry(expression: trimmedExpression, result: result, date: Date()),
            at: 0
        )

        if calculations.count > 100 {
            calculations = Array(calculations.prefix(100))
        }

        save()
    }

    func clear() {
        calculations = []
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: BuckyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let file = CalculationHistoryFile(calculations: calculations)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save calculation history at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}

private enum ArithmeticEvaluator {
    static func evaluate(_ input: String) -> String? {
        let expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isArithmeticInput(expression) else { return nil }

        do {
            var parser = ArithmeticParser(expression)
            let value = try parser.parse()
            guard value.isFinite else { return nil }
            return format(value)
        } catch {
            return nil
        }
    }

    static func isArithmeticInput(_ input: String) -> Bool {
        let expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "0123456789+-*/×÷()., \t\n")
        return expression.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    static func shouldStoreInHistory(_ input: String) -> Bool {
        containsBinaryArithmeticOperator(input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func containsBinaryArithmeticOperator(_ value: String) -> Bool {
        var previousNonWhitespace: UnicodeScalar?

        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if "+-*/×÷".unicodeScalars.contains(scalar) {
                if let previousNonWhitespace,
                   !"+-*/×÷(".unicodeScalars.contains(previousNonWhitespace) {
                    return true
                }
            }

            previousNonWhitespace = scalar
        }

        return false
    }

    private static func format(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000000001,
           rounded >= Double(Int64.min),
           rounded <= Double(Int64.max) {
            return String(Int64(rounded))
        }

        return resultFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.10g", value)
    }

    private static let resultFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}

private enum ArithmeticEvaluationError: Error {
    case expectedNumber
    case unexpectedInput
    case unmatchedParenthesis
    case divisionByZero
}

private struct ArithmeticParser {
    private let scalars: [UnicodeScalar]
    private var index = 0

    init(_ expression: String) {
        scalars = Array(expression.unicodeScalars)
    }

    mutating func parse() throws -> Double {
        let value = try parseExpression()
        skipWhitespace()
        guard index == scalars.count else {
            throw ArithmeticEvaluationError.unexpectedInput
        }
        return value
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()

        while true {
            skipWhitespace()
            if match("+") {
                value += try parseTerm()
            } else if match("-") {
                value -= try parseTerm()
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseFactor()

        while true {
            skipWhitespace()
            if match("*") || match("×") {
                value *= try parseFactor()
            } else if match("/") || match("÷") {
                let divisor = try parseFactor()
                guard divisor != 0 else {
                    throw ArithmeticEvaluationError.divisionByZero
                }
                value /= divisor
            } else {
                return value
            }
        }
    }

    private mutating func parseFactor() throws -> Double {
        skipWhitespace()

        if match("+") {
            return try parseFactor()
        }

        if match("-") {
            let value = try parseFactor()
            return -value
        }

        if match("(") {
            let value = try parseExpression()
            guard match(")") else {
                throw ArithmeticEvaluationError.unmatchedParenthesis
            }
            return value
        }

        return try parseNumber()
    }

    private mutating func parseNumber() throws -> Double {
        skipWhitespace()
        let start = index
        var sawDigit = false
        var sawDecimal = false

        while index < scalars.count {
            let scalar = scalars[index]

            if CharacterSet.decimalDigits.contains(scalar) {
                sawDigit = true
                index += 1
            } else if scalar == ".", !sawDecimal {
                sawDecimal = true
                index += 1
            } else if scalar == "," {
                index += 1
            } else {
                break
            }
        }

        guard sawDigit else {
            throw ArithmeticEvaluationError.expectedNumber
        }

        let numberText = String(String.UnicodeScalarView(Array(scalars[start..<index])))
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(numberText) else {
            throw ArithmeticEvaluationError.expectedNumber
        }
        return value
    }

    private mutating func skipWhitespace() {
        while index < scalars.count,
              CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
            index += 1
        }
    }

    private mutating func match(_ value: String) -> Bool {
        guard let scalar = value.unicodeScalars.first,
              index < scalars.count,
              scalars[index] == scalar else {
            return false
        }

        index += 1
        return true
    }
}

private enum DictionaryLookup {
    static func results(for input: String, limit: Int = 8) -> [DictionaryResult] {
        let term = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }

        var results: [DictionaryResult] = []
        var seenTerms = Set<String>()

        appendResult(for: term, to: &results, seenTerms: &seenTerms)

        for candidate in fuzzyCandidates(for: term) {
            guard results.count < limit else { break }
            appendResult(for: candidate, to: &results, seenTerms: &seenTerms)
        }

        return results
    }

    private static func appendResult(
        for term: String,
        to results: inout [DictionaryResult],
        seenTerms: inout Set<String>
    ) {
        let normalizedTerm = normalized(term)
        guard seenTerms.insert(normalizedTerm).inserted,
              let definition = definition(for: term) else {
            return
        }

        results.append(DictionaryResult(term: term, definition: definition))
    }

    private static func definition(for term: String) -> String? {
        let rangeLength = (term as NSString).length
        guard rangeLength > 0,
              let definition = DCSCopyTextDefinition(
                nil,
                term as CFString,
                CFRange(location: 0, length: rangeLength)
              )?.takeRetainedValue() as String? else {
            return nil
        }

        let trimmedDefinition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDefinition.isEmpty ? nil : trimmedDefinition
    }

    private static func fuzzyCandidates(for term: String) -> [String] {
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (term as NSString).length)
        let completions = checker.completions(
            forPartialWordRange: range,
            in: term,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []
        let guesses = checker.guesses(
            forWordRange: range,
            in: term,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []

        var seen = Set<String>()
        return (completions + guesses)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { candidateScore($0, query: term) > candidateScore($1, query: term) }
            .filter { seen.insert(normalized($0)).inserted }
    }

    private static func candidateScore(_ candidate: String, query: String) -> Int {
        let normalizedCandidate = normalized(candidate)
        let normalizedQuery = normalized(query)

        if normalizedCandidate == normalizedQuery {
            return 10_000
        }
        if normalizedCandidate.hasPrefix(normalizedQuery) {
            return 9_000 - min(normalizedCandidate.count, 500)
        }
        if normalizedCandidate.contains(normalizedQuery) {
            return 7_000 - min(normalizedCandidate.count, 500)
        }

        return 5_000 - min(levenshteinDistance(normalizedCandidate, normalizedQuery), 50) * 80
    }

    private static func levenshteinDistance(_ left: String, _ right: String) -> Int {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)

        guard !leftCharacters.isEmpty else { return rightCharacters.count }
        guard !rightCharacters.isEmpty else { return leftCharacters.count }

        var previous = Array(0...rightCharacters.count)
        var current = Array(repeating: 0, count: rightCharacters.count + 1)

        for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
            current[0] = leftIndex + 1

            for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + substitutionCost
                )
            }

            swap(&previous, &current)
        }

        return previous[rightCharacters.count]
    }
}

private enum LauncherCommand {
    case up
    case down
    case open
    case close
    case reindex
    case settings
    case toggleToolsMode
    case clearHistory
    case togglePin
}

private final class LauncherSearchField: NSSearchField {
    var commandHandler: ((LauncherCommand) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isCommandR, commandHandler?(.reindex) == true {
            return true
        }
        if event.isCommandComma, commandHandler?(.settings) == true {
            return true
        }
        if event.isToolsShortcut, commandHandler?(.toggleToolsMode) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.isToolsShortcut, commandHandler?(.toggleToolsMode) == true {
            return
        }

        switch event.keyCode {
        case 126:
            if commandHandler?(.up) == true { return }
        case 125:
            if commandHandler?(.down) == true { return }
        case 36, 76:
            if commandHandler?(.open) == true { return }
        case 53:
            if commandHandler?(.close) == true { return }
        default:
            break
        }

        super.keyDown(with: event)
    }
}

private final class FloatingPanel: NSPanel {
    var commandHandler: ((LauncherCommand) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isCommandR, commandHandler?(.reindex) == true {
            return true
        }
        if event.isCommandComma, commandHandler?(.settings) == true {
            return true
        }
        if event.isToolsShortcut, commandHandler?(.toggleToolsMode) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if commandHandler?(.close) != true {
            orderOut(sender)
        }
    }
}

private final class ResizeGripView: NSView {
    var resizeHandler: (() -> Void)?

    private let minimumSize = NSSize(width: 360, height: 300)
    private var initialWindowFrame = NSRect.zero
    private var initialMouseLocation = NSPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Resize"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        toolTip = "Resize"
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialWindowFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        let width = max(minimumSize.width, initialWindowFrame.width + deltaX)
        let height = max(minimumSize.height, initialWindowFrame.height - deltaY)
        let frame = NSRect(
            x: initialWindowFrame.minX,
            y: initialWindowFrame.maxY - height,
            width: width,
            height: height
        )

        window.setFrame(frame, display: true)
        resizeHandler?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.tertiaryLabelColor.setStroke()

        for offset in [5.0, 9.0, 13.0] {
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + offset))
            path.stroke()
        }
    }
}

private final class ResultCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ResultCellView")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let excludeButton = NSButton(title: "", target: nil, action: nil)
    private var onExclude: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    func configure(with item: LaunchItem, onExclude: @escaping () -> Void) {
        self.onExclude = onExclude
        iconView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
        excludeButton.isHidden = false
        excludeButton.isEnabled = true
        updateColors()
    }

    func configure(with item: ToolItem) {
        onExclude = nil
        iconView.image = Self.icon(for: item.kind)
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
        excludeButton.isHidden = true
        excludeButton.isEnabled = false
        updateColors()
    }

    private func buildView() {
        identifier = Self.reuseIdentifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        excludeButton.translatesAutoresizingMaskIntoConstraints = false
        excludeButton.target = self
        excludeButton.action = #selector(excludeClicked)
        excludeButton.bezelStyle = .texturedRounded
        excludeButton.setButtonType(.momentaryPushIn)
        excludeButton.contentTintColor = .secondaryLabelColor
        excludeButton.toolTip = "Hide"
        excludeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide") {
            excludeButton.image = image
            excludeButton.imagePosition = .imageOnly
        } else {
            excludeButton.title = "Hide"
            excludeButton.font = .systemFont(ofSize: 11, weight: .medium)
        }

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        addSubview(iconView)
        addSubview(textStack)
        addSubview(excludeButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: excludeButton.leadingAnchor, constant: -12),

            excludeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            excludeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            excludeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            excludeButton.heightAnchor.constraint(equalToConstant: 26)
        ])

        updateColors()
    }

    private static func icon(for kind: ToolItem.Kind) -> NSImage? {
        let symbolName: String

        switch kind {
        case .calculation:
            symbolName = "equal.circle"
        case .calculationHistory:
            symbolName = "clock.arrow.circlepath"
        case .dictionary:
            symbolName = "book"
        case .message:
            symbolName = "info.circle"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func excludeClicked() {
        onExclude?()
    }

    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        titleLabel.textColor = selected ? .selectedTextColor : .labelColor
        subtitleLabel.textColor = selected ? .selectedTextColor : .secondaryLabelColor
        excludeButton.contentTintColor = selected ? .selectedTextColor : .secondaryLabelColor
    }
}

private final class LauncherWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let panel: FloatingPanel
    private let searchField = LauncherSearchField()
    private let indexingIndicator = NSProgressIndicator()
    private let controlsStack = NSStackView()
    private let clearHistoryButton = NSButton(title: "", target: nil, action: nil)
    private let pinButton = NSButton(title: "", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let resizeGripView = ResizeGripView()
    private let indexer = ApplicationIndexer()
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let calculationHistoryStore: CalculationHistoryStore
    private let openSettingsAction: () -> Void

    private var mode: LauncherMode = .applications
    private var allItems: [LaunchItem] = []
    private var filteredItems: [LaunchItem] = []
    private var toolItems: [ToolItem] = []
    private var isIndexing = false
    private var needsReindexAfterCurrent = false
    private var pendingCalculationHistoryTimer: Timer?
    private var pendingCalculationHistoryExpression: String?
    private var pendingCalculationHistoryResult: String?
    private var localKeyMonitor: Any?
    private var isPinned = false

    init(
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        calculationHistoryStore: CalculationHistoryStore,
        openSettingsAction: @escaping () -> Void
    ) {
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.calculationHistoryStore = calculationHistoryStore
        self.openSettingsAction = openSettingsAction
        let contentRect = NSRect(x: 0, y: 0, width: 720, height: 430)
        panel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        buildWindow()
        installLocalKeyMonitor()
        reindex()
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func toggle() {
        guard !isPinned else { return }

        if panel.isVisible && mode == .applications {
            hide()
        } else {
            show()
        }
    }

    func show() {
        show(mode: .applications)
    }

    private func show(mode: LauncherMode) {
        self.mode = mode
        updateModeChrome()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        searchField.stringValue = ""
        applyCurrentMode()
        searchField.becomeFirstResponder()

        if mode == .applications {
            DispatchQueue.main.async { [weak self] in
                self?.reindex()
            }
        }
    }

    func hide() {
        cancelPendingCalculationHistory()
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        panel.resignKey()
        panel.invalidateCursorRects(for: panel.contentView ?? NSView())
        NSCursor.arrow.set()
    }

    func reindex() {
        guard !isIndexing else {
            needsReindexAfterCurrent = true
            setIndexing(true)
            return
        }

        isIndexing = true
        needsReindexAfterCurrent = false
        inclusionStore.load()
        exclusionStore.load()
        if mode == .applications {
            setIndexing(true)
            updateEmptyState(query: searchField.stringValue)
        }

        let includedPaths = inclusionStore.includedPaths
        DispatchQueue.global(qos: .userInitiated).async { [indexer] in
            let items = indexer.load(includedPaths: includedPaths)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.allItems = items
                self.isIndexing = false

                if self.needsReindexAfterCurrent {
                    self.reindex()
                    if self.mode == .applications {
                        self.applyFilter()
                    }
                } else {
                    if self.mode == .applications {
                        self.setIndexing(false)
                        self.applyFilter()
                    }
                }
            }
        }
    }

    private func buildWindow() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 360, height: 300)
        panel.commandHandler = { [weak self] command in
            self?.handle(command: command) ?? false
        }

        let rootView = NSVisualEffectView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.material = .hudWindow
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 8
        rootView.layer?.masksToBounds = true
        panel.contentView = rootView

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.placeholderString = "Search for Apps"
        searchField.font = .systemFont(ofSize: 18, weight: .medium)
        searchField.focusRingType = .none
        searchField.commandHandler = { [weak self] command in
            self?.handle(command: command) ?? false
        }

        indexingIndicator.translatesAutoresizingMaskIntoConstraints = false
        indexingIndicator.style = .spinning
        indexingIndicator.controlSize = .small
        indexingIndicator.isIndeterminate = true
        indexingIndicator.isDisplayedWhenStopped = false
        indexingIndicator.isHidden = true

        clearHistoryButton.translatesAutoresizingMaskIntoConstraints = false
        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistoryClicked)
        clearHistoryButton.bezelStyle = .texturedRounded
        clearHistoryButton.setButtonType(.momentaryPushIn)
        clearHistoryButton.toolTip = "Clear calculation history"
        clearHistoryButton.isHidden = true
        if let image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear history") {
            clearHistoryButton.image = image
            clearHistoryButton.imagePosition = .imageOnly
        } else {
            clearHistoryButton.title = "Clear"
        }

        pinButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        pinButton.bezelStyle = .texturedRounded
        pinButton.setButtonType(.toggle)
        pinButton.toolTip = "Pin tools window"
        pinButton.isHidden = true
        if let image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin") {
            pinButton.image = image
            pinButton.imagePosition = .imageOnly
        } else {
            pinButton.title = "Pin"
        }

        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 6
        controlsStack.detachesHiddenViews = true
        controlsStack.addArrangedSubview(indexingIndicator)
        controlsStack.addArrangedSubview(clearHistoryButton)
        controlsStack.addArrangedSubview(pinButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.backgroundColor = .clear
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelected)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ResultColumn"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 0
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.isHidden = true

        resizeGripView.translatesAutoresizingMaskIntoConstraints = false
        resizeGripView.resizeHandler = { [weak self] in
            self?.panel.contentView?.layoutSubtreeIfNeeded()
            self?.resizeResultColumn()
        }

        rootView.addSubview(searchField)
        rootView.addSubview(controlsStack)
        rootView.addSubview(scrollView)
        rootView.addSubview(emptyLabel)
        rootView.addSubview(resizeGripView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: controlsStack.leadingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 42),

            controlsStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            controlsStack.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            indexingIndicator.widthAnchor.constraint(equalToConstant: 18),
            indexingIndicator.heightAnchor.constraint(equalToConstant: 18),
            clearHistoryButton.widthAnchor.constraint(equalToConstant: 30),
            clearHistoryButton.heightAnchor.constraint(equalToConstant: 26),
            pinButton.widthAnchor.constraint(equalToConstant: 30),
            pinButton.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -18),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            resizeGripView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -4),
            resizeGripView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -2),
            resizeGripView.widthAnchor.constraint(equalToConstant: 22),
            resizeGripView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel.isVisible,
                  (self.panel.isKeyWindow || self.panel.isMainWindow),
                  event.isToolsShortcut else {
                return event
            }

            return self.handle(command: .toggleToolsMode) ? nil : event
        }
    }

    private func updateModeChrome() {
        switch mode {
        case .applications:
            searchField.placeholderString = "Search for Apps"
            clearHistoryButton.isHidden = true
            pinButton.isHidden = true
            if isPinned {
                setPinned(false)
            }
            if isIndexing {
                setIndexing(true)
            } else {
                setIndexing(false)
            }
        case .tools:
            searchField.placeholderString = "Calculate Numbers and Define Words"
            setIndexing(false)
            clearHistoryButton.isHidden = false
            pinButton.isHidden = false
        }
        updatePinButton()
        updateClearHistoryButton()
    }

    private var inputIsBlank: Bool {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func clearHistoryClicked() {
        calculationHistoryStore.clear()
        applyToolsResults(scheduleHistory: false)
        searchField.becomeFirstResponder()
    }

    @objc private func pinClicked() {
        setPinned(!isPinned)
        searchField.becomeFirstResponder()
    }

    private func setPinned(_ pinned: Bool) {
        guard isPinned != pinned else {
            updatePinButton()
            return
        }

        isPinned = pinned
        panel.isMovableByWindowBackground = pinned
        panel.level = pinned ? .statusBar : .floating
        updatePinButton()
    }

    private func updatePinButton() {
        pinButton.state = isPinned ? .on : .off
        pinButton.toolTip = isPinned ? "Unpin tools window" : "Pin tools window"

        let symbolName = isPinned ? "pin.fill" : "pin"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            pinButton.image = image
            pinButton.imagePosition = .imageOnly
        }
    }

    private func updateClearHistoryButton() {
        clearHistoryButton.isEnabled = mode == .tools && !calculationHistoryStore.calculations.isEmpty
    }

    private func toggleToolsModeFromShortcut() -> Bool {
        guard inputIsBlank, !isPinned else { return false }

        switch mode {
        case .applications:
            switchMode(to: .tools)
        case .tools:
            switchMode(to: .applications)
        }

        return true
    }

    private func switchMode(to nextMode: LauncherMode) {
        guard mode != nextMode else { return }

        mode = nextMode
        searchField.stringValue = ""
        updateModeChrome()
        applyCurrentMode()
        searchField.becomeFirstResponder()

        if nextMode == .applications {
            DispatchQueue.main.async { [weak self] in
                self?.reindex()
            }
        }
    }

    private func applyCurrentMode() {
        switch mode {
        case .applications:
            cancelPendingCalculationHistory()
            applyFilter()
        case .tools:
            calculationHistoryStore.load()
            applyToolsResults()
        }
    }

    private func applyToolsResults(scheduleHistory: Bool = true) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelPendingCalculationHistory()

        if query.isEmpty {
            toolItems = calculationHistoryItems()
        } else if ArithmeticEvaluator.isArithmeticInput(query) {
            if let result = ArithmeticEvaluator.evaluate(query) {
                toolItems = [
                    ToolItem(
                        title: result,
                        subtitle: "\(query) =",
                        copyText: result,
                        kind: .calculation
                    )
                ] + calculationHistoryItems(excludingExpression: query, result: result)

                if scheduleHistory, ArithmeticEvaluator.shouldStoreInHistory(query) {
                    scheduleCalculationHistory(expression: query, result: result)
                }
            } else {
                toolItems = [
                    ToolItem(
                        title: "Complete the calculation",
                        subtitle: query,
                        copyText: nil,
                        kind: .message
                    )
                ] + calculationHistoryItems()
            }
        } else {
            let dictionaryResults = DictionaryLookup.results(for: query)

            if !dictionaryResults.isEmpty {
                toolItems = dictionaryResults.map { result in
                    ToolItem(
                        title: result.term,
                        subtitle: Self.singleLine(result.definition),
                        copyText: nil,
                        kind: .dictionary
                    )
                }
            } else {
                toolItems = [
                    ToolItem(
                        title: "No dictionary matches",
                        subtitle: query,
                        copyText: nil,
                        kind: .message
                    )
                ]
            }
        }

        resizeResultColumn()
        tableView.reloadData()
        selectFirstResult()
        updateToolsEmptyState(query: query)
        updateClearHistoryButton()
    }

    private func calculationHistoryItems(
        excludingExpression expression: String? = nil,
        result excludedResult: String? = nil
    ) -> [ToolItem] {
        calculationHistoryStore.calculations.compactMap { entry in
            if entry.expression == expression && entry.result == excludedResult {
                return nil
            }

            return ToolItem(
                title: "\(entry.expression) = \(entry.result)",
                subtitle: "Calculated \(Self.calculationHistoryDateFormatter.string(from: entry.date))",
                copyText: entry.result,
                kind: .calculationHistory
            )
        }
    }

    private func scheduleCalculationHistory(expression: String, result: String) {
        pendingCalculationHistoryExpression = expression
        pendingCalculationHistoryResult = result
        pendingCalculationHistoryTimer = Timer.scheduledTimer(
            withTimeInterval: 0.7,
            repeats: false
        ) { [weak self] _ in
            self?.commitPendingCalculationHistory(refreshResults: true)
        }
    }

    private func commitPendingCalculationHistory(refreshResults: Bool) {
        guard let expression = pendingCalculationHistoryExpression,
              let result = pendingCalculationHistoryResult else {
            return
        }

        cancelPendingCalculationHistory()
        calculationHistoryStore.add(expression: expression, result: result)

        if refreshResults, mode == .tools {
            applyToolsResults(scheduleHistory: false)
        }
    }

    private func cancelPendingCalculationHistory() {
        pendingCalculationHistoryTimer?.invalidate()
        pendingCalculationHistoryTimer = nil
        pendingCalculationHistoryExpression = nil
        pendingCalculationHistoryResult = nil
    }

    private func updateToolsEmptyState(query: String) {
        if toolItems.isEmpty {
            emptyLabel.stringValue = query.isEmpty ? "No calculation history" : "No tool results"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private static let calculationHistoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func singleLine(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func setIndexing(_ indexing: Bool) {
        if indexing {
            indexingIndicator.isHidden = false
            indexingIndicator.startAnimation(nil)
        } else {
            indexingIndicator.stopAnimation(nil)
            indexingIndicator.isHidden = true
        }
    }

    private func positionPanel() {
        guard let screen = Self.primaryScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(720, max(360, visibleFrame.width - 40))
        let height = min(430, max(300, visibleFrame.height - 80))
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.maxY - height - 96
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        resizeResultColumn()
    }

    static func primaryScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == mainDisplayID
        }
    }

    private func resizeResultColumn() {
        guard let column = tableView.tableColumns.first else { return }
        let fallbackWidth = panel.contentView?.bounds.width ?? panel.frame.width
        let width = max(0, scrollView.contentSize.width > 0 ? scrollView.contentSize.width : fallbackWidth)
        column.width = width
        tableView.frame.size.width = width
    }

    private func applyFilter(preservePreviousOnEmpty: Bool = false) {
        let query = searchField.stringValue
        let visibleItems = allItems.filter { !exclusionStore.isExcluded($0) }
        let nextItems = Self.filter(visibleItems, query: query)

        if preservePreviousOnEmpty,
           nextItems.isEmpty,
           !filteredItems.isEmpty,
           !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyLabel.isHidden = true
            return
        }

        filteredItems = nextItems
        resizeResultColumn()
        tableView.reloadData()
        selectFirstResult()
        updateEmptyState(query: query)
    }

    private static func filter(_ items: [LaunchItem], query: String) -> [LaunchItem] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else {
            return Array(items.prefix(80))
        }

        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return items.compactMap { item -> (LaunchItem, Int)? in
            guard tokens.allSatisfy({ item.searchText.contains($0) }) else {
                return nil
            }

            let title = normalized(item.title)
            var score = 0

            for token in tokens {
                if title == token {
                    score += 1200
                } else if title.hasPrefix(token) {
                    score += 1000
                } else if title.split(separator: " ").contains(where: { $0.hasPrefix(token) }) {
                    score += 850
                } else if title.contains(token) {
                    score += 650
                } else {
                    score += 350
                }
            }

            score -= min(item.title.count, 120)
            return (item, score)
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
            }
            return $0.1 > $1.1
        }
        .prefix(80)
        .map(\.0)
    }

    private var displayedResultCount: Int {
        switch mode {
        case .applications:
            return filteredItems.count
        case .tools:
            return toolItems.count
        }
    }

    private func selectFirstResult() {
        guard displayedResultCount > 0 else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    private func updateEmptyState(query: String) {
        if filteredItems.isEmpty {
            if isIndexing && allItems.isEmpty {
                emptyLabel.stringValue = "Loading apps"
            } else {
                emptyLabel.stringValue = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "No launchable items found"
                    : "No matches"
            }
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private func handle(command: LauncherCommand) -> Bool {
        switch command {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
        case .open:
            openSelected()
        case .close:
            clearInputOrHide()
        case .reindex:
            reindex()
        case .settings:
            openSettingsAction()
        case .toggleToolsMode:
            return toggleToolsModeFromShortcut()
        case .clearHistory:
            clearHistoryClicked()
        case .togglePin:
            pinClicked()
        }
        return true
    }

    private func clearInputOrHide() {
        if inputIsBlank {
            if isPinned {
                setPinned(false)
            }
            hide()
            return
        }

        searchField.stringValue = ""
        applyCurrentMode()
        searchField.becomeFirstResponder()
    }

    private func moveSelection(by delta: Int) {
        let count = displayedResultCount
        guard count > 0 else { return }
        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = max(0, min(count - 1, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func openSelected() {
        let row = tableView.selectedRow
        switch mode {
        case .applications:
            guard row >= 0, row < filteredItems.count else { return }
            let item = filteredItems[row]
            hide()
            launch(item)
        case .tools:
            guard row >= 0, row < toolItems.count else { return }
            activate(toolItems[row])
        }
    }

    private func launch(_ item: LaunchItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: configuration) { _, error in
            if let error {
                NSLog("Bucky failed to open %@: %@", item.url.path, error.localizedDescription)
            }
        }
    }

    private func exclude(_ item: LaunchItem) {
        exclusionStore.exclude(item)
        applyFilter()
    }

    private func activate(_ item: ToolItem) {
        switch item.kind {
        case .calculation:
            commitPendingCalculationHistory(refreshResults: false)
            copyToPasteboard(item.copyText)
        case .calculationHistory:
            copyToPasteboard(item.copyText)
        case .dictionary:
            openDictionary(term: item.title)
        case .message:
            return
        }

        if !isPinned {
            hide()
        }
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func openDictionary(term: String) {
        guard let escapedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://\(escapedTerm)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refreshAfterExclusionsChanged() {
        if mode == .applications {
            applyFilter()
        }
    }

    func refreshAfterInclusionsChanged() {
        reindex()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedResultCount
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        54
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCellView.reuseIdentifier, owner: self) as? ResultCellView
            ?? ResultCellView(frame: .zero)

        switch mode {
        case .applications:
            let item = filteredItems[row]
            cell.configure(with: item) { [weak self] in
                self?.exclude(item)
            }
        case .tools:
            cell.configure(with: toolItems[row])
        }
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        switch mode {
        case .applications:
            applyFilter(preservePreviousOnEmpty: true)
        case .tools:
            applyToolsResults()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            return handle(command: .up)
        case #selector(NSResponder.moveDown(_:)):
            return handle(command: .down)
        case #selector(NSResponder.insertNewline(_:)):
            return handle(command: .open)
        case #selector(NSResponder.cancelOperation(_:)):
            return handle(command: .close)
        default:
            return false
        }
    }
}

private enum LaunchAtStartupController {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

private final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let settingsStore: SettingsStore
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let hotKeyChangeHandler: (HotKeyConfiguration) -> Bool
    private let inclusionsChangedHandler: () -> Void
    private let exclusionsChangedHandler: () -> Void

    private let hotKeyButton = NSButton(title: "", target: nil, action: nil)
    private let launchAtStartupCheckbox = NSButton(checkboxWithTitle: "Launch on startup", target: nil, action: nil)
    private let inclusionsTableView = NSTableView()
    private let addInclusionButton = NSButton(title: "Add...", target: nil, action: nil)
    private let removeInclusionButton = NSButton(title: "Remove", target: nil, action: nil)
    private let exclusionsTableView = NSTableView()
    private let removeExclusionButton = NSButton(title: "Remove", target: nil, action: nil)
    private var inclusionPaths: [String] = []
    private var exclusionPaths: [String] = []
    private var hotKeyEventMonitor: Any?
    private var isRecordingHotKey = false

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        hotKeyChangeHandler: @escaping (HotKeyConfiguration) -> Bool,
        inclusionsChangedHandler: @escaping () -> Void,
        exclusionsChangedHandler: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.hotKeyChangeHandler = hotKeyChangeHandler
        self.inclusionsChangedHandler = inclusionsChangedHandler
        self.exclusionsChangedHandler = exclusionsChangedHandler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bucky Settings"
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildWindow()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        stopRecordingHotKey()
    }

    func show() {
        refresh()
        positionWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        guard let contentView = window?.contentView else { return }

        let rootStack = NSStackView()
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        contentView.addSubview(rootStack)

        let hotKeyLabel = NSTextField(labelWithString: "Hotkey")
        hotKeyLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        hotKeyButton.translatesAutoresizingMaskIntoConstraints = false
        hotKeyButton.target = self
        hotKeyButton.action = #selector(startRecordingHotKey)
        hotKeyButton.bezelStyle = .rounded
        hotKeyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let hotKeyRow = NSStackView(views: [hotKeyLabel, hotKeyButton])
        hotKeyRow.translatesAutoresizingMaskIntoConstraints = false
        hotKeyRow.orientation = .horizontal
        hotKeyRow.alignment = .centerY
        hotKeyRow.spacing = 12

        launchAtStartupCheckbox.translatesAutoresizingMaskIntoConstraints = false
        launchAtStartupCheckbox.target = self
        launchAtStartupCheckbox.action = #selector(launchAtStartupChanged)

        let inclusionsLabel = NSTextField(labelWithString: "Included apps")
        inclusionsLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let inclusionsScrollView = NSScrollView()
        inclusionsScrollView.translatesAutoresizingMaskIntoConstraints = false
        inclusionsScrollView.hasVerticalScroller = true
        inclusionsScrollView.autohidesScrollers = true
        inclusionsScrollView.hasHorizontalScroller = false
        inclusionsScrollView.borderType = .bezelBorder

        inclusionsTableView.translatesAutoresizingMaskIntoConstraints = false
        inclusionsTableView.headerView = nil
        inclusionsTableView.rowHeight = 28
        inclusionsTableView.usesAlternatingRowBackgroundColors = true
        inclusionsTableView.allowsEmptySelection = true
        inclusionsTableView.delegate = self
        inclusionsTableView.dataSource = self

        let inclusionsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("IncludedPathColumn"))
        inclusionsColumn.resizingMask = .autoresizingMask
        inclusionsTableView.addTableColumn(inclusionsColumn)
        inclusionsScrollView.documentView = inclusionsTableView

        addInclusionButton.translatesAutoresizingMaskIntoConstraints = false
        addInclusionButton.target = self
        addInclusionButton.action = #selector(addIncludedApp)
        addInclusionButton.bezelStyle = .rounded

        removeInclusionButton.translatesAutoresizingMaskIntoConstraints = false
        removeInclusionButton.target = self
        removeInclusionButton.action = #selector(removeSelectedInclusion)
        removeInclusionButton.bezelStyle = .rounded

        let inclusionsButtonsRow = NSStackView(views: [addInclusionButton, removeInclusionButton])
        inclusionsButtonsRow.translatesAutoresizingMaskIntoConstraints = false
        inclusionsButtonsRow.orientation = .horizontal
        inclusionsButtonsRow.alignment = .centerY
        inclusionsButtonsRow.spacing = 8

        let inclusionsStack = NSStackView(views: [inclusionsLabel, inclusionsScrollView, inclusionsButtonsRow])
        inclusionsStack.translatesAutoresizingMaskIntoConstraints = false
        inclusionsStack.orientation = .vertical
        inclusionsStack.alignment = .leading
        inclusionsStack.spacing = 8

        let exclusionsLabel = NSTextField(labelWithString: "Hidden apps")
        exclusionsLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        exclusionsTableView.translatesAutoresizingMaskIntoConstraints = false
        exclusionsTableView.headerView = nil
        exclusionsTableView.rowHeight = 28
        exclusionsTableView.usesAlternatingRowBackgroundColors = true
        exclusionsTableView.allowsEmptySelection = true
        exclusionsTableView.delegate = self
        exclusionsTableView.dataSource = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PathColumn"))
        column.resizingMask = .autoresizingMask
        exclusionsTableView.addTableColumn(column)
        scrollView.documentView = exclusionsTableView

        removeExclusionButton.translatesAutoresizingMaskIntoConstraints = false
        removeExclusionButton.target = self
        removeExclusionButton.action = #selector(removeSelectedExclusion)
        removeExclusionButton.bezelStyle = .rounded

        let exclusionsStack = NSStackView(views: [exclusionsLabel, scrollView, removeExclusionButton])
        exclusionsStack.translatesAutoresizingMaskIntoConstraints = false
        exclusionsStack.orientation = .vertical
        exclusionsStack.alignment = .leading
        exclusionsStack.spacing = 8

        rootStack.addArrangedSubview(hotKeyRow)
        rootStack.addArrangedSubview(launchAtStartupCheckbox)
        rootStack.addArrangedSubview(inclusionsStack)
        rootStack.addArrangedSubview(exclusionsStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            hotKeyRow.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            hotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

            inclusionsStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            inclusionsScrollView.heightAnchor.constraint(equalToConstant: 150),
            inclusionsScrollView.leadingAnchor.constraint(equalTo: inclusionsStack.leadingAnchor),
            inclusionsScrollView.trailingAnchor.constraint(equalTo: inclusionsStack.trailingAnchor),
            addInclusionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            removeInclusionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),

            exclusionsStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 150),
            scrollView.leadingAnchor.constraint(equalTo: exclusionsStack.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: exclusionsStack.trailingAnchor),
            removeExclusionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
    }

    private func positionWindow() {
        guard let window, let screen = LauncherWindowController.primaryScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            window?.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.midY - frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func refresh() {
        settingsStore.load()
        inclusionStore.load()
        exclusionStore.load()
        hotKeyButton.title = settingsStore.settings.hotKey.displayName
        launchAtStartupCheckbox.state = settingsStore.settings.launchAtStartup ? .on : .off
        refreshInclusions()
        refreshExclusions()
    }

    private func refreshInclusions() {
        inclusionPaths = inclusionStore.sortedPaths()
        inclusionsTableView.reloadData()
        updateRemoveButtons()
    }

    private func refreshExclusions() {
        exclusionPaths = exclusionStore.sortedPaths()
        exclusionsTableView.reloadData()
        updateRemoveButtons()
    }

    @objc private func startRecordingHotKey() {
        guard !isRecordingHotKey else { return }
        isRecordingHotKey = true
        hotKeyButton.title = "Press shortcut"

        hotKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecordingHotKey else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecordingHotKey()
                self.hotKeyButton.title = self.settingsStore.settings.hotKey.displayName
                return nil
            }

            guard let hotKey = HotKeyConfiguration(event: event) else {
                NSSound.beep()
                return nil
            }

            if self.hotKeyChangeHandler(hotKey) {
                self.settingsStore.updateHotKey(hotKey)
                self.hotKeyButton.title = hotKey.displayName
            } else {
                self.hotKeyButton.title = self.settingsStore.settings.hotKey.displayName
            }

            self.stopRecordingHotKey()
            return nil
        }
    }

    private func stopRecordingHotKey() {
        isRecordingHotKey = false
        if let hotKeyEventMonitor {
            NSEvent.removeMonitor(hotKeyEventMonitor)
            self.hotKeyEventMonitor = nil
        }
    }

    @objc private func launchAtStartupChanged() {
        let enabled = launchAtStartupCheckbox.state == .on

        do {
            try LaunchAtStartupController.setEnabled(enabled)
            settingsStore.updateLaunchAtStartup(enabled)
        } catch {
            launchAtStartupCheckbox.state = settingsStore.settings.launchAtStartup ? .on : .off
            showError(title: "Could not update launch at startup", error: error)
        }
    }

    @objc private func addIncludedApp() {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.title = "Add Included App"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.applicationBundle]

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.inclusionStore.add(path: url.path)
            }
            self.refreshInclusions()
            self.inclusionsChangedHandler()
        }
    }

    @objc private func removeSelectedInclusion() {
        let row = inclusionsTableView.selectedRow
        guard row >= 0, row < inclusionPaths.count else { return }
        inclusionStore.remove(path: inclusionPaths[row])
        refreshInclusions()
        inclusionsChangedHandler()
    }

    @objc private func removeSelectedExclusion() {
        let row = exclusionsTableView.selectedRow
        guard row >= 0, row < exclusionPaths.count else { return }
        exclusionStore.remove(path: exclusionPaths[row])
        refreshExclusions()
        exclusionsChangedHandler()
    }

    private func updateRemoveButtons() {
        removeInclusionButton.isEnabled = inclusionsTableView.selectedRow >= 0
        removeExclusionButton.isEnabled = exclusionsTableView.selectedRow >= 0
    }

    private func showError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window ?? NSWindow())
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === inclusionsTableView {
            return inclusionPaths.count
        }
        return exclusionPaths.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = tableView === inclusionsTableView
            ? NSUserInterfaceItemIdentifier("InclusionCell")
            : NSUserInterfaceItemIdentifier("ExclusionCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.stringValue = tableView === inclusionsTableView
            ? inclusionPaths[row]
            : exclusionPaths[row]

        if cell.textField == nil {
            cell.identifier = identifier
            cell.textField = textField
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButtons()
    }
}

private final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openAction: () -> Void
    private let reindexAction: () -> Void
    private let settingsAction: () -> Void

    init(
        openAction: @escaping () -> Void,
        reindexAction: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) {
        self.openAction = openAction
        self.reindexAction = reindexAction
        self.settingsAction = settingsAction
        super.init()
        buildMenu()
    }

    private func buildMenu() {
        if let button = statusItem.button {
            button.image = nil
            button.title = "🦾"
            button.font = .systemFont(ofSize: 16)
            button.toolTip = "Bucky"
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Bucky", action: #selector(open), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let reindexItem = NSMenuItem(title: "Reindex Applications", action: #selector(reindex), keyEquivalent: "")
        reindexItem.target = self
        menu.addItem(reindexItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Bucky", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func open() {
        openAction()
    }

    @objc private func reindex() {
        reindexAction()
    }

    @objc private func settings() {
        settingsAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    let configuration: HotKeyConfiguration
    private let hotKeyIdentifier: UInt32
    private let onHotKey: () -> Void

    init(
        configuration: HotKeyConfiguration,
        identifier: UInt32 = 1,
        onHotKey: @escaping () -> Void
    ) throws {
        self.configuration = configuration
        hotKeyIdentifier = identifier
        self.onHotKey = onHotKey
        try install()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func install() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr,
                      hotKeyID.signature == "Bcky".fourCharCode,
                      hotKeyID.id == controller.hotKeyIdentifier else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    controller.onHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.installHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: "Bcky".fourCharCode, id: hotKeyIdentifier)
        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            throw HotKeyError.register(registrationStatus)
        }
    }
}

private enum HotKeyError: LocalizedError {
    case installHandler(OSStatus)
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return "Could not install hotkey handler. OSStatus \(status)."
        case .register(let status):
            return "Could not register hotkey. OSStatus \(status)."
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let inclusionStore = InclusionStore()
    private let exclusionStore = ExclusionStore()
    private let calculationHistoryStore = CalculationHistoryStore()
    private var launcherController: LauncherWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var statusMenuController: StatusMenuController?
    private var hotKeyController: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let launcherController = LauncherWindowController(
            inclusionStore: inclusionStore,
            exclusionStore: exclusionStore,
            calculationHistoryStore: calculationHistoryStore,
            openSettingsAction: { [weak self] in self?.showSettings() }
        )
        self.launcherController = launcherController

        statusMenuController = StatusMenuController(
            openAction: { [weak launcherController] in launcherController?.show() },
            reindexAction: { [weak launcherController] in launcherController?.reindex() },
            settingsAction: { [weak self] in self?.showSettings() }
        )

        _ = registerHotKey(settingsStore.settings.hotKey)
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                inclusionStore: inclusionStore,
                exclusionStore: exclusionStore,
                hotKeyChangeHandler: { [weak self] hotKey in
                    self?.registerHotKey(hotKey) ?? false
                },
                inclusionsChangedHandler: { [weak self] in
                    self?.launcherController?.refreshAfterInclusionsChanged()
                },
                exclusionsChangedHandler: { [weak self] in
                    self?.launcherController?.refreshAfterExclusionsChanged()
                }
            )
        }

        settingsWindowController?.show()
    }

    private func registerHotKey(_ hotKey: HotKeyConfiguration) -> Bool {
        if hotKeyController?.configuration == hotKey {
            return true
        }

        do {
            let controller = try HotKeyController(configuration: hotKey) { [weak self] in
                self?.launcherController?.toggle()
            }
            hotKeyController = controller
            return true
        } catch {
            showHotKeyAlert(error, hotKey: hotKey)
            return false
        }
    }

    private func showHotKeyAlert(_ error: Error, hotKey: HotKeyConfiguration) {
        let alert = NSAlert()
        alert.messageText = "Bucky could not register \(hotKey.displayName)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private func normalized(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0

    if deviceFlags.contains(.control) {
        modifiers |= UInt32(controlKey)
    }
    if deviceFlags.contains(.option) {
        modifiers |= UInt32(optionKey)
    }
    if deviceFlags.contains(.shift) {
        modifiers |= UInt32(shiftKey)
    }
    if deviceFlags.contains(.command) {
        modifiers |= UInt32(cmdKey)
    }

    return modifiers
}

private func carbonModifierDisplayNames(_ modifiers: UInt32) -> [String] {
    var names: [String] = []

    if modifiers & UInt32(controlKey) != 0 {
        names.append("Control")
    }
    if modifiers & UInt32(optionKey) != 0 {
        names.append("Option")
    }
    if modifiers & UInt32(shiftKey) != 0 {
        names.append("Shift")
    }
    if modifiers & UInt32(cmdKey) != 0 {
        names.append("Command")
    }

    return names
}

private func displayKeyName(for keyCode: UInt32, characters: String?) -> String {
    switch Int(keyCode) {
    case kVK_Space:
        return "Space"
    case kVK_Return:
        return "Return"
    case kVK_Tab:
        return "Tab"
    case kVK_Escape:
        return "Escape"
    case kVK_Delete:
        return "Delete"
    case kVK_ForwardDelete:
        return "Forward Delete"
    case kVK_LeftArrow:
        return "Left"
    case kVK_RightArrow:
        return "Right"
    case kVK_UpArrow:
        return "Up"
    case kVK_DownArrow:
        return "Down"
    case kVK_Home:
        return "Home"
    case kVK_End:
        return "End"
    case kVK_PageUp:
        return "Page Up"
    case kVK_PageDown:
        return "Page Down"
    default:
        break
    }

    guard let characters, !characters.isEmpty else {
        return "Key \(keyCode)"
    }

    if characters == "," {
        return "Comma"
    }

    let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "Key \(keyCode)"
    }

    return trimmed.uppercased()
}

private extension HotKeyConfiguration {
    init?(event: NSEvent) {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            return nil
        }

        let keyCode = UInt32(event.keyCode)
        self.init(
            keyCode: keyCode,
            modifiers: modifiers,
            keyName: displayKeyName(for: keyCode, characters: event.charactersIgnoringModifiers)
        )
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}

private extension NSEvent {
    var isCommandR: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && charactersIgnoringModifiers?.lowercased() == "r"
    }

    var isCommandComma: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && charactersIgnoringModifiers == ","
    }

    var isToolsShortcut: Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowedFlags: NSEvent.ModifierFlags = [.command, .option, .control]
        let isSlashKey = keyCode == UInt16(kVK_ANSI_Slash) || charactersIgnoringModifiers == "/"
        return flags.contains(.shift)
            && flags.intersection(disallowedFlags).isEmpty
            && isSlashKey
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
