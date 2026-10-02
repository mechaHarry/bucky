import Foundation

enum BuckyPaths {
    static var appSupportDirectory: URL {
        // Explicit override isolates tests/development runs from the user's saved data.
        if let directory = ProcessInfo.processInfo.environment["BUCKY_DATA_DIRECTORY"], directory.hasPrefix("/") {
            return URL(fileURLWithPath: directory, isDirectory: true)
        }
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportDirectory.appendingPathComponent("Bucky", isDirectory: true)
    }
}
