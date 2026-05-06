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
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillInputVerticalOffset, 0)
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
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillInputVerticalOffset, 0)
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillIconVerticalOffset(for: .applications), 0)
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillIconVerticalOffset(for: .calculator), 0)
        XCTAssertEqual(ModeSwitcherLayoutPolicy.activeTextPillIconVerticalOffset(for: .dictionary), 0)
    }

    func testTextInputFieldEditorIsVerticallyCenteredInsideControlBounds() {
        let frame = ModeSwitcherLayoutPolicy.activeTextPillEditorFrame(
            in: CGRect(x: 0, y: 0, width: 300, height: 30),
            editorHeight: 24
        )

        XCTAssertEqual(frame.origin.y, 3)
        XCTAssertEqual(frame.height, 24)
        XCTAssertEqual(frame.midY, 15)
    }

    func testTextInputFieldRequestsFocusWhenWindowArrivesAfterSwiftUIFocus() {
        XCTAssertTrue(ModeSwitcherTextFieldFocusPolicy.shouldRequestFirstResponder(
            isFocused: true,
            hasWindow: true,
            hasCurrentEditor: false
        ))
        XCTAssertFalse(ModeSwitcherTextFieldFocusPolicy.shouldRequestFirstResponder(
            isFocused: true,
            hasWindow: false,
            hasCurrentEditor: false
        ))
        XCTAssertFalse(ModeSwitcherTextFieldFocusPolicy.shouldRequestFirstResponder(
            isFocused: true,
            hasWindow: true,
            hasCurrentEditor: true
        ))
    }

    func testTextInputFieldDoesNotClearSwiftUIFocusWhenAppKitTemporarilyEndsEditing() {
        XCTAssertFalse(ModeSwitcherTextFieldFocusPolicy.shouldPublishFocusEnd(isFocusRequested: true))
        XCTAssertTrue(ModeSwitcherTextFieldFocusPolicy.shouldPublishFocusEnd(isFocusRequested: false))
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
