import XCTest
@testable import Bucky

final class AgendaRemovalContractTests: XCTestCase {
    func testAgendaRuntimeIsRemoved() throws {
        XCTAssertEqual(LauncherMode.ordered, [.applications, .files])

        XCTAssertEqual(LauncherMode(commandNumber: 1), .applications)
        XCTAssertNil(LauncherMode(commandNumber: 2))
        XCTAssertNil(LauncherMode(commandNumber: 3))
        XCTAssertEqual(LauncherMode(commandNumber: 4), .files)
        XCTAssertNil(LauncherMode(commandNumber: 5))

        XCTAssertEqual(LauncherMode.applications.previousMode, .files)
        XCTAssertEqual(LauncherMode.applications.nextMode, .files)
        XCTAssertEqual(LauncherMode.files.previousMode, .applications)
        XCTAssertEqual(LauncherMode.files.nextMode, .applications)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for path in [
            "Sources/Bucky/Agenda/AgendaModels.swift",
            "Sources/Bucky/Agenda/AgendaStore.swift",
            "Sources/Bucky/UI/SwiftUI/AgendaView.swift",
            "Tests/BuckyTests/AgendaStoreTests.swift"
        ] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path)
        }

        let sharedRuntimePaths = [
            "Sources/Bucky/Models/CoreModels.swift",
            "Sources/Bucky/UI/Shared/LauncherCommand.swift",
            "Sources/Bucky/UI/Shared/Utilities.swift",
            "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift",
            "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift",
            "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift",
            "Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift",
            "Sources/Bucky/UI/SwiftUI/LauncherModeTintPolicy.swift",
            "Sources/Bucky/UI/SwiftUI/SettingsView.swift"
        ]
        for path in sharedRuntimePaths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(source.localizedCaseInsensitiveContains("agenda"), path)
        }
    }
}
