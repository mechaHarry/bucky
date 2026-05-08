import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum MacFileServicesError: LocalizedError {
    case cannotReplaceItemWithItself(URL)
    case cannotOpen(URL)
    case invalidName(String)
    case targetAlreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case let .cannotReplaceItemWithItself(url):
            return "Cannot replace an item with itself: \(url.path)"
        case let .cannotOpen(url):
            return "Could not open: \(url.path)"
        case let .invalidName(name):
            return "Invalid file name: \(name)"
        case let .targetAlreadyExists(url):
            return "A file already exists at: \(url.path)"
        }
    }
}

struct MacFileServices: FileBrowserNativeServicing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw MacFileServicesError.cannotOpen(url)
        }
    }

    func revealInFinder(_ urls: [URL]) throws {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPathsToPasteboard(_ urls: [URL]) throws {
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
            let originalDestination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            if canonicalFileURL(source) == canonicalFileURL(originalDestination) {
                if conflict == .replace {
                    throw MacFileServicesError.cannotReplaceItemWithItself(source)
                }
                continue
            }

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

    func rename(_ url: URL, to proposedName: String) throws -> URL {
        let target = try renameTarget(for: url, proposedName: proposedName)
        try fileManager.moveItem(at: url, to: target)
        return target
    }

    func batchRename(_ urls: [URL], baseName: String) throws -> [URL] {
        let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateFileName(trimmedBaseName)

        let targets = try urls.enumerated().map { offset, url in
            let extensionSuffix = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let proposedName = "\(trimmedBaseName) \(offset + 1)\(extensionSuffix)"
            return try renameTarget(for: url, proposedName: proposedName)
        }

        let uniqueTargets = Set(targets.map { canonicalFileURL($0) })
        guard uniqueTargets.count == targets.count else {
            throw MacFileServicesError.invalidName(baseName)
        }

        let canonicalSources = Set(urls.map { canonicalFileURL($0) })
        for (source, target) in zip(urls, targets) {
            let canonicalSource = canonicalFileURL(source)
            let canonicalTarget = canonicalFileURL(target)
            if canonicalSource != canonicalTarget, canonicalSources.contains(canonicalTarget) {
                throw MacFileServicesError.targetAlreadyExists(target)
            }
        }

        for target in targets {
            let isSource = urls.contains { canonicalFileURL($0) == canonicalFileURL(target) }
            if !isSource, fileManager.fileExists(atPath: target.path) {
                throw MacFileServicesError.targetAlreadyExists(target)
            }
        }

        for (source, target) in zip(urls, targets) where canonicalFileURL(source) != canonicalFileURL(target) {
            try fileManager.moveItem(at: source, to: target)
        }

        return targets
    }

    func conflictingDestinations(for urls: [URL], in destinationDirectory: URL) -> [FileBrowserConflict] {
        urls.compactMap { source in
            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            guard fileManager.fileExists(atPath: destination.path),
                  canonicalFileURL(source) != canonicalFileURL(destination) else {
                return nil
            }
            return FileBrowserConflict(source: source, destination: destination)
        }
    }

    func previewMode(for url: URL) -> FileBrowserPreviewMode {
        let previewURL = previewContentURL(for: url)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: previewURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .metadataFallback
        }

        let pathExtension = previewURL.pathExtension.lowercased()
        if Self.codePreviewExtensions.contains(pathExtension) {
            return .codeText
        }

        if let type = try? previewURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           Self.videoPreviewTypes.contains(where: { type.conforms(to: $0) }) {
            return .video
        }

        if let type = UTType(filenameExtension: pathExtension),
           Self.videoPreviewTypes.contains(where: { type.conforms(to: $0) }) {
            return .video
        }

        if let type = try? previewURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           Self.nativePreviewTypes.contains(where: { type.conforms(to: $0) }) {
            return .nativeThumbnail
        }

        if let type = UTType(filenameExtension: pathExtension),
           Self.nativePreviewTypes.contains(where: { type.conforms(to: $0) }) {
            return .nativeThumbnail
        }

        return .metadataFallback
    }

    func previewContentURL(for url: URL) -> URL {
        let standardized = url.standardizedFileURL

        if let resolvedAlias = try? URL(resolvingAliasFileAt: standardized),
           existingPreviewFileURL(for: resolvedAlias) != nil {
            return resolvedAlias.standardizedFileURL
        }

        let resolvedSymlink = standardized.resolvingSymlinksInPath()
        if resolvedSymlink.path != standardized.path,
           existingPreviewFileURL(for: resolvedSymlink) != nil {
            return resolvedSymlink.standardizedFileURL
        }

        return standardized
    }

    func loadPreviewThumbnail(
        for url: URL,
        size: CGSize,
        scale: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) {
        let request = QLThumbnailGenerator.Request(
            fileAt: previewContentURL(for: url),
            size: size,
            scale: scale,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
            DispatchQueue.main.async {
                completion(thumbnail?.nsImage)
            }
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

    private func existingPreviewFileURL(for url: URL) -> URL? {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }

        return url.standardizedFileURL
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
        if canonicalFileURL(source) == canonicalFileURL(destination) {
            throw MacFileServicesError.cannotReplaceItemWithItself(source)
        }
    }

    private func canonicalFileURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func replacementTemporaryURL(for destination: URL) -> URL {
        destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).replacement-\(UUID().uuidString)")
    }

    private func renameTarget(for url: URL, proposedName: String) throws -> URL {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateFileName(trimmedName)
        let target = url.deletingLastPathComponent().appendingPathComponent(trimmedName)

        if canonicalFileURL(url) != canonicalFileURL(target), fileManager.fileExists(atPath: target.path) {
            throw MacFileServicesError.targetAlreadyExists(target)
        }

        return target
    }

    private func validateFileName(_ name: String) throws {
        guard !name.isEmpty,
              !name.contains("/"),
              name != ".",
              name != ".." else {
            throw MacFileServicesError.invalidName(name)
        }
    }

    private static let nativePreviewTypes: [UTType] = [
        .image,
        .pdf
    ]

    private static let videoPreviewTypes: [UTType] = [
        .movie,
        .mpeg4Movie,
        .quickTimeMovie
    ]

    private static let codePreviewExtensions: Set<String> = [
        "bash", "c", "cc", "conf", "cpp", "css", "go", "h", "hpp",
        "html", "ini", "java", "js", "json", "jsx", "m", "markdown",
        "md", "mm", "pem", "plist", "py", "rb", "rs", "scss", "sh",
        "sql", "swift", "tf", "toml", "ts", "tsx", "txt", "xml", "yaml",
        "yml", "zsh"
    ]
}
