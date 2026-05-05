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
}
