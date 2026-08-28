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

    func testNameSortDoesNotForceDirectoriesBeforeFilesByDefault() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "readme".write(to: temporaryDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .name, foldersFirst: false)

        XCTAssertEqual(entries.map(\.name), ["README.md", "Sources"])
        XCTAssertEqual(entries.first?.kind, .file)
    }

    func testFoldersFirstOptionGroupsDirectoriesBeforeFiles() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "readme".write(to: temporaryDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .name, foldersFirst: true)

        XCTAssertEqual(entries.map(\.name), ["Sources", "README.md"])
        XCTAssertEqual(entries.first?.kind, .directory)
    }

    func testSortBySizeOrdersEntriesDescendingWithoutForcingDirectoriesFirst() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try "12345".write(to: temporaryDirectory.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)
        try "1".write(to: temporaryDirectory.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .size, foldersFirst: false)

        XCTAssertEqual(entries.map(\.name), ["large.txt", "small.txt", "Folder"])
    }

    func testSortByDateCreatedOrdersDatedEntriesBeforeNilDates() {
        let entries = [
            entry(named: "NewerFile.txt", kind: .file, createdAt: Date(timeIntervalSince1970: 2)),
            entry(named: "OlderFolder", kind: .directory, createdAt: Date(timeIntervalSince1970: 1)),
            entry(named: "Undated.txt", kind: .file, createdAt: nil)
        ]

        let sorted = FileSystemClient.sorted(entries, by: .dateCreated, foldersFirst: false)

        XCTAssertEqual(sorted.map(\.name), ["NewerFile.txt", "OlderFolder", "Undated.txt"])
    }

    func testSortByDateCreatedCanStillGroupFoldersFirst() {
        let entries = [
            entry(named: "NewerFile.txt", kind: .file, createdAt: Date(timeIntervalSince1970: 2)),
            entry(named: "OlderFolder", kind: .directory, createdAt: Date(timeIntervalSince1970: 1))
        ]

        let sorted = FileSystemClient.sorted(entries, by: .dateCreated, foldersFirst: true)

        XCTAssertEqual(sorted.map(\.name), ["OlderFolder", "NewerFile.txt"])
    }

    func testParentURLStopsAtRoot() {
        let client = FileSystemClient()

        XCTAssertEqual(client.parentURL(for: TestFixtures.userHome), TestFixtures.userRoot)
        XCTAssertNil(client.parentURL(for: URL(fileURLWithPath: "/")))
    }

    func testIsDirectoryDistinguishesDirectoriesFromFiles() throws {
        let directory = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
        let file = temporaryDirectory.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "notes".write(to: file, atomically: true, encoding: .utf8)

        let client = FileSystemClient()

        XCTAssertTrue(client.isDirectory(directory))
        XCTAssertFalse(client.isDirectory(file))
    }

    func testIsDirectoryFollowsSymbolicLinksToDirectories() throws {
        let target = TestFixtures.sampleCloudTargetDirectory(in: temporaryDirectory)
        let link = TestFixtures.sampleCloudTargetLink(in: temporaryDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(FileSystemClient().isDirectory(link))
    }

    func testResolvedDirectoryURLFollowsSymbolicLinksToDirectoryTargets() throws {
        let target = TestFixtures.sampleCloudTargetDirectory(in: temporaryDirectory)
        let link = TestFixtures.sampleCloudTargetLink(in: temporaryDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertEqual(FileSystemClient().resolvedDirectoryURL(for: link), target.standardizedFileURL)
    }

    private func entry(
        named name: String,
        kind: FileBrowserEntry.Kind = .file,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil
    ) -> FileBrowserEntry {
        FileBrowserEntry(
            url: temporaryDirectory.appendingPathComponent(name),
            kind: kind,
            size: nil,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isHidden: name.hasPrefix(".")
        )
    }
}
