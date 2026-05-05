import XCTest
@testable import Bucky

final class MacFileServicesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyMacFileServicesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testKeepBothURLAddsNumericSuffixBeforeExtension() {
        let destination = temporaryDirectory.appendingPathComponent("Report.txt")
        try? "old".write(to: destination, atomically: true, encoding: .utf8)

        let url = MacFileServices(fileManager: .default).keepBothURL(for: destination)

        XCTAssertEqual(url.lastPathComponent, "Report 2.txt")
    }

    func testCopyFilesCopiesIntoDestinationDirectory() throws {
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        let destination = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try "value".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try MacFileServices(fileManager: .default).copy([source], to: destination, conflict: .replace)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("source.txt").path))
    }

    func testCopyReplaceIntoSourceParentPreservesSource() throws {
        let source = temporaryDirectory.appendingPathComponent("same.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try MacFileServices(fileManager: .default).copy([source], to: temporaryDirectory, conflict: .replace))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    func testCopyReplaceThroughSymlinkIntoRealParentPreservesSource() throws {
        let realDirectory = temporaryDirectory.appendingPathComponent("Real", isDirectory: true)
        let symlinkDirectory = temporaryDirectory.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: realDirectory)
        let realSource = realDirectory.appendingPathComponent("same.txt")
        let symlinkSource = symlinkDirectory.appendingPathComponent("same.txt")
        try "original".write(to: realSource, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try MacFileServices(fileManager: .default).copy([symlinkSource], to: realDirectory, conflict: .replace))
        XCTAssertEqual(try String(contentsOf: realSource, encoding: .utf8), "original")
    }

    func testMoveFilesMovesIntoDestinationDirectory() throws {
        let source = temporaryDirectory.appendingPathComponent("move.txt")
        let destination = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try "value".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try MacFileServices(fileManager: .default).move([source], to: destination, conflict: .replace)

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("move.txt").path))
    }

    func testMoveReplaceIntoSourceParentPreservesSource() throws {
        let source = temporaryDirectory.appendingPathComponent("same-move.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try MacFileServices(fileManager: .default).move([source], to: temporaryDirectory, conflict: .replace))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    func testMoveReplaceThroughSymlinkIntoRealParentPreservesSource() throws {
        let realDirectory = temporaryDirectory.appendingPathComponent("Real", isDirectory: true)
        let symlinkDirectory = temporaryDirectory.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: realDirectory)
        let realSource = realDirectory.appendingPathComponent("same-move.txt")
        let symlinkSource = symlinkDirectory.appendingPathComponent("same-move.txt")
        try "original".write(to: realSource, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try MacFileServices(fileManager: .default).move([symlinkSource], to: realDirectory, conflict: .replace))
        XCTAssertEqual(try String(contentsOf: realSource, encoding: .utf8), "original")
    }

    func testMoveKeepBothIntoSourceParentDoesNotRenameSource() throws {
        let source = temporaryDirectory.appendingPathComponent("same-move.txt")
        let keepBothDestination = temporaryDirectory.appendingPathComponent("same-move 2.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)

        try MacFileServices(fileManager: .default).move([source], to: temporaryDirectory, conflict: .keepBoth)

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: keepBothDestination.path))
    }

    func testMoveKeepBothThroughSymlinkIntoRealParentDoesNotRenameSource() throws {
        let realDirectory = temporaryDirectory.appendingPathComponent("Real", isDirectory: true)
        let symlinkDirectory = temporaryDirectory.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: realDirectory)
        let realSource = realDirectory.appendingPathComponent("same-move.txt")
        let symlinkSource = symlinkDirectory.appendingPathComponent("same-move.txt")
        let keepBothDestination = realDirectory.appendingPathComponent("same-move 2.txt")
        try "original".write(to: realSource, atomically: true, encoding: .utf8)

        try MacFileServices(fileManager: .default).move([symlinkSource], to: realDirectory, conflict: .keepBoth)

        XCTAssertEqual(try String(contentsOf: realSource, encoding: .utf8), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: keepBothDestination.path))
    }

    func testConflictingDestinationsReportsExistingDestinationWithoutSelfConflict() throws {
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        let destination = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "old".write(to: destination.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)

        let conflicts = MacFileServices(fileManager: .default).conflictingDestinations(for: [source], in: destination)

        XCTAssertEqual(conflicts, [
            FileBrowserConflict(source: source, destination: destination.appendingPathComponent("source.txt"))
        ])
        XCTAssertEqual(MacFileServices(fileManager: .default).conflictingDestinations(for: [source], in: temporaryDirectory), [])
    }

    func testRenameMovesItemWithoutOverwritingExistingFile() throws {
        let source = temporaryDirectory.appendingPathComponent("old.txt")
        let existing = temporaryDirectory.appendingPathComponent("existing.txt")
        try "value".write(to: source, atomically: true, encoding: .utf8)
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        let services = MacFileServices(fileManager: .default)

        let renamed = try services.rename(source, to: "new.txt")

        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "value")
        XCTAssertThrowsError(try services.rename(renamed, to: "existing.txt"))
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing")
    }

    func testBatchRenameAddsNumberedSuffixesAndPreservesExtensions() throws {
        let first = temporaryDirectory.appendingPathComponent("one.txt")
        let second = temporaryDirectory.appendingPathComponent("two.md")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let renamed = try MacFileServices(fileManager: .default).batchRename([first, second], baseName: "Screenshot")

        XCTAssertEqual(renamed.map(\.lastPathComponent), ["Screenshot 1.txt", "Screenshot 2.md"])
        XCTAssertEqual(try String(contentsOf: renamed[0], encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: renamed[1], encoding: .utf8), "two")
    }

    func testBatchRenameRejectsExistingTargetBeforeMovingAnyFile() throws {
        let first = temporaryDirectory.appendingPathComponent("one.txt")
        let second = temporaryDirectory.appendingPathComponent("two.txt")
        let existing = temporaryDirectory.appendingPathComponent("Screenshot 1.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)
        try "existing".write(to: existing, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try MacFileServices(fileManager: .default).batchRename([first, second], baseName: "Screenshot"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing")
    }

    func testBatchRenameRejectsSelectedSourceTargetCollisionBeforeMovingAnyFile() throws {
        let first = temporaryDirectory.appendingPathComponent("Screenshot 2.txt")
        let second = temporaryDirectory.appendingPathComponent("other.txt")
        let wouldBeFirstTarget = temporaryDirectory.appendingPathComponent("Screenshot 1.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try MacFileServices(fileManager: .default).batchRename([first, second], baseName: "Screenshot"))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wouldBeFirstTarget.path))
    }

    func testPreviewModeUsesNativeThumbnailForSupportedFilesAndFallbackOtherwise() throws {
        let textFile = temporaryDirectory.appendingPathComponent("notes.txt")
        let unsupportedFile = temporaryDirectory.appendingPathComponent("archive.buckyblob")
        let directory = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
        try "notes".write(to: textFile, atomically: true, encoding: .utf8)
        try "blob".write(to: unsupportedFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let services = MacFileServices(fileManager: .default)

        XCTAssertEqual(services.previewMode(for: textFile), .nativeThumbnail)
        XCTAssertEqual(services.previewMode(for: unsupportedFile), .metadataFallback)
        XCTAssertEqual(services.previewMode(for: directory), .metadataFallback)
    }
}
