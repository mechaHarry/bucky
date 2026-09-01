import Foundation

struct CountdownsFile: Codable {
    var countdowns: [Countdown]
}

final class CountdownStore {
    private static let maximumCountdowns = 100
    private static let maximumFileBytes = 128 * 1_024
    private let fileManager = FileManager.default

    private(set) var countdowns: [Countdown] = []
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? BuckyPaths.appSupportDirectory.appendingPathComponent("countdowns.json")
        load()
    }

    func load() {
        do {
            let fileSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
            guard fileSize?.intValue ?? 0 <= Self.maximumFileBytes else {
                throw CocoaError(.fileReadTooLarge)
            }
            let file = try JSONFilePersistence.read(
                CountdownsFile.self,
                from: fileURL,
                decoder: JSONFilePersistence.makeDecoder()
            )
            countdowns = Self.sanitized(file.countdowns)
            if countdowns != file.countdowns {
                save()
            }
        } catch CocoaError.fileReadNoSuchFile {
            countdowns = []
        } catch {
            NSLog("Bucky could not read countdowns: %@", error.localizedDescription)
            countdowns = []
        }
    }

    @discardableResult
    func add(name: String, targetDate: Date) -> Countdown? {
        guard let name = Self.normalizedName(name) else { return nil }

        let countdown = Countdown(name: name, targetDate: targetDate)
        countdowns.insert(countdown, at: 0)
        countdowns = Array(countdowns.prefix(Self.maximumCountdowns))
        save()
        return countdown
    }

    @discardableResult
    func update(id: UUID, name: String, targetDate: Date) -> Bool {
        guard let name = Self.normalizedName(name),
              let index = countdowns.firstIndex(where: { $0.id == id }) else {
            return false
        }

        countdowns[index].name = name
        countdowns[index].targetDate = targetDate
        save()
        return true
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let index = countdowns.firstIndex(where: { $0.id == id }) else {
            return false
        }

        countdowns.remove(at: index)
        save()
        return true
    }

    private func save() {
        do {
            try JSONFilePersistence.write(
                CountdownsFile(countdowns: countdowns),
                to: fileURL,
                fileManager: fileManager,
                encoder: JSONFilePersistence.makeEncoder()
            )
        } catch {
            NSLog("Bucky could not save countdowns: %@", error.localizedDescription)
        }
    }

    private static func normalizedName(_ value: String) -> String? {
        let name = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return String(name.prefix(200))
    }

    private static func sanitized(_ values: [Countdown]) -> [Countdown] {
        var seenIDs = Set<UUID>()
        return values.compactMap { countdown in
            guard let name = normalizedName(countdown.name), seenIDs.insert(countdown.id).inserted else {
                return nil
            }
            return Countdown(id: countdown.id, name: name, targetDate: countdown.targetDate)
        }.prefix(maximumCountdowns).map { $0 }
    }
}
