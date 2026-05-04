import XCTest
@testable import Bucky

final class FileSystemClientTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyFileSystemClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDirectoryEntriesIncludeHiddenFilesByDefault() throws {
        try "visible".write(to: temporaryDirectory.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: temporaryDirectory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .name)

        XCTAssertEqual(entries.map(\.name), [".env", "visible.txt"])
        XCTAssertEqual(entries.first?.kind, .file)
    }

    func testDirectoriesSortBeforeFilesByName() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "readme".write(to: temporaryDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .name)

        XCTAssertEqual(entries.map(\.name), ["Sources", "README.md"])
        XCTAssertEqual(entries.first?.kind, .directory)
    }

    func testSortBySizeOrdersFilesDescendingAfterDirectories() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try "12345".write(to: temporaryDirectory.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)
        try "1".write(to: temporaryDirectory.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .size)

        XCTAssertEqual(entries.map(\.name), ["Folder", "large.txt", "small.txt"])
    }

    func testSortByDateCreatedOrdersDatedEntriesBeforeNilDates() {
        let entries = [
            entry(named: "aaa-undated.txt", createdAt: nil),
            entry(named: "zzz-dated.txt", createdAt: Date(timeIntervalSince1970: 1))
        ]

        let sorted = FileSystemClient.sorted(entries, by: .dateCreated)

        XCTAssertEqual(sorted.map(\.name), ["zzz-dated.txt", "aaa-undated.txt"])
    }

    func testParentURLStopsAtRoot() {
        let client = FileSystemClient()

        XCTAssertEqual(client.parentURL(for: URL(fileURLWithPath: "/Users/harriche")), URL(fileURLWithPath: "/Users"))
        XCTAssertNil(client.parentURL(for: URL(fileURLWithPath: "/")))
    }

    private func entry(named name: String, createdAt: Date? = nil, modifiedAt: Date? = nil) -> FileBrowserEntry {
        FileBrowserEntry(
            url: temporaryDirectory.appendingPathComponent(name),
            kind: .file,
            size: nil,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isHidden: name.hasPrefix(".")
        )
    }
}
