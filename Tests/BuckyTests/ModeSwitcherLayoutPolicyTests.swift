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
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight,
            ModeSwitcherLayoutPolicy.activePillHeight - ModeSwitcherLayoutPolicy.activeTextPillVerticalInset * 2
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillInputHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillTextFieldHeight,
            ModeSwitcherLayoutPolicy.activeTextPillControlHeight
        )
        XCTAssertLessThanOrEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize,
            ModeSwitcherLayoutPolicy.activeTextPillIconWidth
        )
        XCTAssertLessThanOrEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize,
            ModeSwitcherLayoutPolicy.activeTextPillIconHeight
        )
        XCTAssertGreaterThan(
            ModeSwitcherLayoutPolicy.activeTextPillInputLeadingInset,
            ModeSwitcherLayoutPolicy.activeTextPillIconLeadingInset + ModeSwitcherLayoutPolicy.activeTextPillIconWidth
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress: false),
            ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset
        )
        XCTAssertGreaterThan(ModeSwitcherLayoutPolicy.activeTextPillVerticalInset, 0)
        XCTAssertLessThan(ModeSwitcherLayoutPolicy.activeTextPillControlHeight, ModeSwitcherLayoutPolicy.activePillHeight)
    }

    func testTextInputModesUseSharedTextPillLayout() {
        XCTAssertEqual(LauncherMode.ordered.filter(\.acceptsTextInput), [
            .applications,
            .calculator,
            .dictionary
        ])
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .applications))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .calculator))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .dictionary))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .files))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .applications))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .calculator))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .dictionary))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .files))
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillIconLeadingInset,
            ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillInputLeadingInset,
            ModeSwitcherLayoutPolicy.activePillHeight + ModeSwitcherLayoutPolicy.activePillHeight / 12
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset,
            ModeSwitcherLayoutPolicy.activePillHeight / 3
        )
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.launcherHeaderTopInset,
            ModeSwitcherLayoutPolicy.activePillHeight / 12
        )
        XCTAssertEqual(ModeSwitcherLayoutPolicy.launcherHeaderHorizontalInset, 0)
    }

    func testTextInputModesUseMarginsInsteadOfVerticalOffsets() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains(".padding(.leading, ModeSwitcherLayoutPolicy.activeTextPillIconLeadingInset)"))
        XCTAssertTrue(source.contains(".padding(.leading, ModeSwitcherLayoutPolicy.activeTextPillInputLeadingInset)"))
        XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress:"))
        XCTAssertFalse(source.contains("HStack(spacing: ModeSwitcherLayoutPolicy.activeTextPillSpacing)"))
        XCTAssertFalse(source.contains("activeTextPillInputVerticalOffset"))
        XCTAssertFalse(source.contains("activeTextPillIconVerticalOffset"))
        XCTAssertFalse(source.contains(".offset(y:"))
    }

    func testActiveTextPillNormalizesVariableSymbolArtwork() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("private struct ActiveTextPillIcon"))
        XCTAssertTrue(source.contains(".resizable()"))
        XCTAssertTrue(source.contains(".scaledToFit()"))
        XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize"))
    }

    func testActiveTextPillBoxesIconAndTextRelativeToPill() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("ZStack(alignment: .leading)"))
        XCTAssertTrue(source.contains("ActiveTextPillIcon(symbol: symbol)"))
        XCTAssertTrue(source.contains("ActiveTextPillInput("))
        XCTAssertTrue(source.contains("private struct ActiveTextPillInput"))
        XCTAssertTrue(source.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    func testActiveTextPillKeepsTextFieldOutsideControlBackground() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("modeSwitcherElement(for: mode)"))
        XCTAssertTrue(source.contains("private struct ModeControlBackground<ShapeType: InsettableShape>"))
        XCTAssertTrue(source.contains("ModeControlBackground(\n                shape: Capsule()"))
        XCTAssertFalse(source.contains("private struct TextInputPillGlassSurface"))
        XCTAssertFalse(source.contains("TextInputModePill(\n                model: model,\n                mode: mode,\n                symbol: symbol(for: mode),\n                isSearchFocused: $isSearchFocused\n            )\n            .glassEffectID"))
    }

    func testActiveTextPillForegroundSitsAboveControlBackground() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("private struct TextInputPillForegroundLayer"))
        XCTAssertTrue(source.contains(".background {\n            ModeControlBackground("))
        XCTAssertTrue(source.contains("TextInputPillForegroundLayer("))
        XCTAssertFalse(source.contains(".glassEffect(.regular.interactive(), in: Capsule())"))
    }

    func testModeStonesAndPillsUseCheapRowStyleSurfaces() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(source.contains("ModeControlBackground(\n                shape: Circle()"))
        XCTAssertTrue(source.contains("ModeControlBackground(\n                        shape: Capsule()"))
        XCTAssertFalse(source.contains(".buttonStyle(.glass)"))
        XCTAssertFalse(source.contains(".shadow(color: .black.opacity(0.18)"))
        XCTAssertFalse(source.contains(".glassEffect("))
        XCTAssertFalse(source.contains(".glassEffectTransition(.matchedGeometry)"))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .files))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .files))
        XCTAssertFalse(source.contains("headerGlassBackdrop"))
    }

    func testActiveTextPillOwnsForegroundLegibilityOutsideGlass() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("private struct ActiveTextPillPlaceholder"))
        XCTAssertTrue(source.contains("TextField(\"\", text: $text)"))
        XCTAssertTrue(source.contains("Text(placeholder)"))
        XCTAssertTrue(source.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains("ActiveTextPillIcon(symbol: symbol)\n                .foregroundStyle(tint)"))
        XCTAssertFalse(source.contains(".foregroundStyle(.secondary)\n            .frame(\n                width: ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize"))
        XCTAssertFalse(source.contains("TextField(placeholder, text: $text)"))
    }

    func testModeSwitcherTextInputUsesSwiftUITextFieldFocusPath() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("TextField(\"\", text: $text)"))
        XCTAssertTrue(source.contains(".focused($isFocused)"))
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

    private func modeSwitcherSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
