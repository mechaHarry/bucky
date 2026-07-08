import Foundation
import Darwin

enum LegacyAgendaStoreCleanup {
    static func removeStore() {
        removeStore(at: BuckyPaths.legacyAgendaStoreURL, removeItem: removeAgendaEntry)
    }

    static func removeStore(at url: URL) {
        removeStore(at: url, removeItem: removeAgendaEntry)
    }

    static func removeStore(
        at url: URL,
        removeItem: (URL) throws -> Void
    ) {
        do {
            try removeItem(url)
        } catch {
            // Legacy cleanup must never prevent startup.
        }
    }

    private static func removeAgendaEntry(at url: URL) {
        guard url.lastPathComponent == "agenda.json" else { return }

        let path = url.path
        guard path.hasPrefix("/") else { return }
        let components = path.split(separator: "/")
        guard components.last.map(String.init) == "agenda.json" else { return }

        var currentFD = open("/", O_RDONLY | O_DIRECTORY)
        guard currentFD >= 0 else { return }
        defer { close(currentFD) }

        for component in components.dropLast() {
            guard component != ".", component != ".." else { return }
            let nextFD = component.withCString {
                openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            }
            guard nextFD >= 0 else { return }
            close(currentFD)
            currentFD = nextFD
        }

        "agenda.json".withCString { name in
            _ = unlinkat(currentFD, name, 0)
        }
    }
}
