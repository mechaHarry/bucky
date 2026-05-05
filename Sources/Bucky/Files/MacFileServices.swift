import AppKit
import Foundation

enum FileBrowserConflictResolution {
    case keepBoth
    case replace
    case cancel
}

enum MacFileServicesError: LocalizedError {
    case cannotReplaceItemWithItself(URL)

    var errorDescription: String? {
        switch self {
        case let .cannotReplaceItemWithItself(url):
            return "Cannot replace an item with itself: \(url.path)"
        }
    }
}

struct MacFileServices {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPathsToPasteboard(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    func copy(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws {
        for source in urls {
            let destination = resolvedDestination(for: source, in: destinationDirectory, conflict: conflict)
            guard let destination else { return }
            if fileManager.fileExists(atPath: destination.path) {
                try copyReplacingItem(at: destination, with: source)
            } else {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
    }

    func move(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws {
        for source in urls {
            let destination = resolvedDestination(for: source, in: destinationDirectory, conflict: conflict)
            guard let destination else { return }
            if fileManager.fileExists(atPath: destination.path) {
                try moveReplacingItem(at: destination, with: source)
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    func trash(_ urls: [URL]) throws {
        for url in urls {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }

    func keepBothURL(for destination: URL) -> URL {
        let directory = destination.deletingLastPathComponent()
        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension

        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func resolvedDestination(
        for source: URL,
        in destinationDirectory: URL,
        conflict: FileBrowserConflictResolution
    ) -> URL? {
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        switch conflict {
        case .keepBoth:
            return keepBothURL(for: destination)
        case .replace:
            return destination
        case .cancel:
            return nil
        }
    }

    private func copyReplacingItem(at destination: URL, with source: URL) throws {
        try validateReplacement(source: source, destination: destination)

        let temporaryURL = replacementTemporaryURL(for: destination)
        do {
            try fileManager.copyItem(at: source, to: temporaryURL)
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func moveReplacingItem(at destination: URL, with source: URL) throws {
        try copyReplacingItem(at: destination, with: source)
        try fileManager.removeItem(at: source)
    }

    private func validateReplacement(source: URL, destination: URL) throws {
        if source.standardizedFileURL == destination.standardizedFileURL {
            throw MacFileServicesError.cannotReplaceItemWithItself(source)
        }
    }

    private func replacementTemporaryURL(for destination: URL) -> URL {
        destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).replacement-\(UUID().uuidString)")
    }
}
