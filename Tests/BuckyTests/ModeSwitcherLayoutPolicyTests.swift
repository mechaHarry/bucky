import XCTest
@testable import Bucky

final class ModeSwitcherLayoutPolicyTests: XCTestCase {
    func testFilesPathWidthIsIndependentOfPathLength() {
        let shortPathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
            in: 520,
            path: "/Applications/Spotify.app"
        )
        let longPathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
            in: 520,
            path: "/Applications/ThousandEyes Security Endpoint.app/Contents/MacOS/ThousandEyes Security Endpoint"
        )

        XCTAssertEqual(shortPathWidth, longPathWidth)
        XCTAssertEqual(shortPathWidth, 320)
    }

    func testFilesPathWidthNeverGoesNegative() {
        XCTAssertEqual(ModeSwitcherLayoutPolicy.filesPathTextWidth(in: 120, path: "/very/long/path"), 0)
    }

    func testTextPillIconAndInputShareStableVerticalMetrics() {
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillInputHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillInputVerticalOffset, 2)
        XCTAssertLessThan(ModeSwitcherLayoutPolicy.activeTextPillControlHeight, ModeSwitcherLayoutPolicy.activePillHeight)
    }

    func testTextInputModesUseSharedTextPillLayout() {
        XCTAssertEqual(LauncherMode.ordered.filter(\.acceptsTextInput), [
            .applications,
            .calculator,
            .dictionary
        ])
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillSpacing, 12)
    }

    func testTextInputModesUseAppsVerticalAlignment() {
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillInputVerticalOffset, 2)
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillIconVerticalOffset(for: .applications), 0)
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillIconVerticalOffset(for: .calculator), 0)
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillIconVerticalOffset(for: .dictionary), 0)
    }

    func testModeSwitcherTextInputUsesSwiftUITextFieldFocusPath() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("TextField(mode.placeholder, text: $model.query)"))
        XCTAssertTrue(source.contains(".focused($isSearchFocused)"))
        XCTAssertFalse(source.contains("NSViewRepresentable"))
        XCTAssertFalse(source.contains("NSTextField"))
        XCTAssertFalse(source.contains("CenteredLauncherNSTextField"))
        XCTAssertFalse(source.contains("NSTextFieldDelegate"))
    }

    func testFilesPathMarqueeUsesFixedPathWidthInsidePill() {
        let pathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
            in: 420,
            path: "/Users/test/Very Long Folder Name/Deep/File.txt"
        )

        XCTAssertEqual(ModeSwitcherLayoutPolicy.filesPathMarqueeWidth(in: 420), pathWidth)
        XCTAssertLessThan(pathWidth, 420)
    }
}
