import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class CalculationHistoryStore {
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
