import Foundation

enum BuckyPaths {
    static var legacyAgendaStoreURL: URL {
        appSupportDirectory.appendingPathComponent("agenda.json", isDirectory: false)
    }

    static var appSupportDirectory: URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportDirectory.appendingPathComponent("Bucky", isDirectory: true)
    }
}
