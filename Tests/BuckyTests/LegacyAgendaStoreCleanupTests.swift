import Foundation
import Darwin
import XCTest
@testable import Bucky

final class LegacyAgendaStoreCleanupTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        let temporaryPath = FileManager.default.temporaryDirectory.path
            .replacingOccurrences(of: "/var/", with: "/private/var/")
        temporaryDirectory = URL(fileURLWithPath: temporaryPath)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testRemovesStoreWithoutTouchingReferencedNoteOrSibling() throws {
        let storeURL = temporaryDirectory.appendingPathComponent("agenda.json")
        let noteURL = temporaryDirectory.appendingPathComponent("external-note.md")
        let settingsURL = temporaryDirectory.appendingPathComponent("settings.json")
        let noteBytes = Data("private note\n".utf8)
        let settingsBytes = Data("{\"setting\":true}\n".utf8)

        try Data("{\"notePath\":\"\(noteURL.path)\"}\n".utf8).write(to: storeURL)
        try noteBytes.write(to: noteURL)
        try settingsBytes.write(to: settingsURL)

        LegacyAgendaStoreCleanup.removeStore(at: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try Data(contentsOf: noteURL), noteBytes)
        XCTAssertEqual(try Data(contentsOf: settingsURL), settingsBytes)
    }

    func testMissingStoreIsNoOp() {
        let storeURL = temporaryDirectory.appendingPathComponent("agenda.json")

        LegacyAgendaStoreCleanup.removeStore(at: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testRefusesWrongFilename() throws {
        let storeURL = temporaryDirectory.appendingPathComponent("not-agenda.json")
        let storeBytes = Data("must remain\n".utf8)
        try storeBytes.write(to: storeURL)

        LegacyAgendaStoreCleanup.removeStore(at: storeURL)

        XCTAssertEqual(try Data(contentsOf: storeURL), storeBytes)
    }

    func testInjectedRemoveClosureReceivesExactURLAndSwallowsError() {
        let storeURL = temporaryDirectory.appendingPathComponent("agenda.json")
        var receivedURLs: [URL] = []

        LegacyAgendaStoreCleanup.removeStore(at: storeURL) { url in
            receivedURLs.append(url)
            throw NSError(domain: "test", code: 1)
        }

        XCTAssertEqual(receivedURLs, [storeURL])
    }

    func testRefusesStoreWhenSupportDirectoryIsSymlink() throws {
        let externalDirectory = temporaryDirectory.appendingPathComponent("external", isDirectory: true)
        let supportDirectory = temporaryDirectory.appendingPathComponent("Bucky", isDirectory: true)
        let storeURL = supportDirectory.appendingPathComponent("agenda.json")
        let agendaBytes = Data("external agenda\n".utf8)

        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try agendaBytes.write(to: externalDirectory.appendingPathComponent("agenda.json"))
        try FileManager.default.createSymbolicLink(at: supportDirectory, withDestinationURL: externalDirectory)

        LegacyAgendaStoreCleanup.removeStore(at: storeURL)

        XCTAssertEqual(try Data(contentsOf: storeURL), agendaBytes)
    }

    func testRefusesStoreWhenAncestorDirectoryIsSymlink() throws {
        let externalDirectory = temporaryDirectory.appendingPathComponent("external", isDirectory: true)
        let ancestorLink = temporaryDirectory.appendingPathComponent("linked-ancestor", isDirectory: true)
        let storeURL = ancestorLink.appendingPathComponent("nested/agenda.json")
        let agendaURL = externalDirectory.appendingPathComponent("nested/agenda.json")
        let agendaBytes = Data("external ancestor agenda\n".utf8)

        try FileManager.default.createDirectory(at: agendaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try agendaBytes.write(to: agendaURL)
        try FileManager.default.createSymbolicLink(at: ancestorLink, withDestinationURL: externalDirectory)

        LegacyAgendaStoreCleanup.removeStore(at: storeURL)

        XCTAssertEqual(try Data(contentsOf: agendaURL), agendaBytes)
    }

    func testRemovesStoreSymlinkWithoutTouchingTarget() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("agenda-target.json")
        let storeURL = temporaryDirectory.appendingPathComponent("agenda.json")
        let targetBytes = Data("target agenda\n".utf8)

        try targetBytes.write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: storeURL, withDestinationURL: targetURL)

        LegacyAgendaStoreCleanup.removeStore(at: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try Data(contentsOf: targetURL), targetBytes)
    }

    func testAppDelegateUsesLegacyStoreURLImmediatelyAfterAccessoryPolicy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Bucky/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let policy = try XCTUnwrap(source.range(of: "NSApp.setActivationPolicy(.accessory)"))
        let queue = try XCTUnwrap(source.range(of: "DispatchQueue.global(qos: .utility).async {"))
        let cleanup = try XCTUnwrap(source.range(of: "LegacyAgendaStoreCleanup.removeStore()"))
        let launcher = try XCTUnwrap(source.range(of: "makeLauncherController()"))

        XCTAssertLessThan(policy.lowerBound, cleanup.lowerBound)
        XCTAssertLessThan(queue.lowerBound, cleanup.lowerBound)
        XCTAssertLessThan(cleanup.lowerBound, launcher.lowerBound)
    }

    func testProductionCleanupDerivesExactLegacyAgendaURL() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Bucky/Legacy/LegacyAgendaStoreCleanup.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("removeStore(at: BuckyPaths.legacyAgendaStoreURL, removeItem: removeAgendaEntry)"))
    }
}
