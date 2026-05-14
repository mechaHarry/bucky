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
        for mode in LauncherMode.ordered {
            XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: mode))
            XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: mode))
        }
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

    func testActiveTextPillKeepsTextFieldOutsideGlassIdentity() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("TextInputModePill(\n                model: model,\n                mode: mode,\n                symbol: symbol(for: mode),\n                glassNamespace: modeGlassNamespace,"))
        XCTAssertFalse(source.contains("activeTextPillClearedInputLeadingInset"))
        XCTAssertTrue(source.contains("ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: model.mode)"))
        XCTAssertTrue(source.contains("private struct TextInputPillGlassSurface"))
        XCTAssertTrue(source.contains("TextInputPillGlassSurface(tint: LauncherModeTintPolicy.activeColor(for: mode))\n                .glassEffectID(mode, in: glassNamespace)\n                .glassEffectTransition(.matchedGeometry)"))
        XCTAssertFalse(source.contains("TextInputModePill(\n                model: model,\n                mode: mode,\n                symbol: symbol(for: mode),\n                isSearchFocused: $isSearchFocused\n            )\n            .glassEffectID"))
    }

    func testActiveTextPillForegroundSitsAboveGlassSurface() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("private struct TextInputPillForegroundLayer"))
        XCTAssertTrue(source.contains(".background {\n            TextInputPillGlassSurface(tint: LauncherModeTintPolicy.activeColor(for: mode))"))
        XCTAssertTrue(source.contains("TextInputPillForegroundLayer("))
        XCTAssertFalse(source.contains(".glassEffect(.regular.interactive(), in: Capsule())\n            .overlay(alignment: .leading)"))
    }

    func testModeSwitcherUsesActiveModeAwareStoneAreasWithActivePillOverlay() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("GeometryReader { proxy in"))
        XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.inactiveStoneFrame("))
        XCTAssertTrue(source.contains("activeMode: model.mode"))
        XCTAssertTrue(source.contains("availableWidth: proxy.size.width"))
        XCTAssertTrue(source.contains("static func inactiveStoneFrame(for mode: LauncherMode"))
        XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.activePillFrame("))
        XCTAssertTrue(source.contains(".glassEffectTransition(.matchedGeometry)"))
    }

    func testActivePillExpansionFrameGrowsFromSelectedStoneSlot() {
        for availableWidth in [CGFloat(496), 760] {
            let firstMode = LauncherMode.ordered[0]
            let firstInactiveFrame = ModeSwitcherLayoutPolicy.inactiveStoneFrame(
                for: firstMode,
                availableWidth: availableWidth
            )
            let firstHalfwayFrame = ModeSwitcherLayoutPolicy.activePillFrame(
                for: firstMode,
                availableWidth: availableWidth,
                expansionProgress: 0.5
            )

            XCTAssertEqual(
                ModeSwitcherLayoutPolicy.activePillFrame(
                    for: firstMode,
                    availableWidth: availableWidth,
                    expansionProgress: 0
                ),
                firstInactiveFrame
            )
            XCTAssertEqual(firstHalfwayFrame.minX, firstInactiveFrame.minX)

            for mode in LauncherMode.ordered.dropFirst() {
                assertActivePillExpandsFromTrailingStoneEdge(
                    mode: mode,
                    availableWidth: availableWidth
                )
            }
        }
    }

    func testModeSwitcherAnimatesActivePillExpansionAboveStableStoneLayer() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("@State private var activePillExpansionProgress"))
        XCTAssertTrue(source.contains("expansionProgress: activePillExpansionProgress"))
        XCTAssertTrue(source.contains(".clipped()"))
        XCTAssertTrue(source.contains(".zIndex(ModeSwitcherLayoutPolicy.activePillZIndex)"))
        XCTAssertTrue(source.contains(".zIndex(ModeSwitcherLayoutPolicy.inactiveStoneZIndex)"))
        XCTAssertTrue(source.contains(".onChange(of: model.mode)"))
    }

    func testSlidingActivePillStartsAtItsInactiveStoneSlot() {
        for availableWidth in [CGFloat(496), 520, 760] {
            for mode in LauncherMode.ordered {
                let inactiveFrame = ModeSwitcherLayoutPolicy.inactiveStoneFrame(
                    for: mode,
                    availableWidth: availableWidth
                )
                let activeFrame = ModeSwitcherLayoutPolicy.activePillFrame(
                    for: mode,
                    availableWidth: availableWidth
                )

                XCTAssertEqual(activeFrame.minX, inactiveFrame.minX)
                XCTAssertEqual(activeFrame.height, inactiveFrame.height)
            }
        }
    }

    func testInactiveStoneSlotsUseCompactModeOrder() {
        for availableWidth in [CGFloat(496), 520, 760] {
            let slotWidth = ModeSwitcherLayoutPolicy.inactiveStoneSlotWidth
            let slotStride = slotWidth + ModeSwitcherLayoutPolicy.modeSwitcherSpacing

            for (index, mode) in LauncherMode.ordered.enumerated() {
                XCTAssertEqual(
                    ModeSwitcherLayoutPolicy.inactiveStoneFrame(for: mode, availableWidth: availableWidth).minX,
                    CGFloat(index) * slotStride
                )
                XCTAssertEqual(
                    ModeSwitcherLayoutPolicy.inactiveStoneFrame(for: mode, availableWidth: availableWidth).width,
                    slotWidth
                )
            }
        }
    }

    func testInactiveStoneFramesStayOutsideActivePillFrame() {
        for availableWidth in [CGFloat(496), 520, 760] {
            for activeMode in LauncherMode.ordered {
                let activeFrame = ModeSwitcherLayoutPolicy.activePillFrame(
                    for: activeMode,
                    availableWidth: availableWidth
                )

                for inactiveMode in LauncherMode.ordered where inactiveMode != activeMode {
                    let inactiveFrame = ModeSwitcherLayoutPolicy.inactiveStoneFrame(
                        for: inactiveMode,
                        activeMode: activeMode,
                        availableWidth: availableWidth
                    )
                    let gap = max(
                        activeFrame.minX - inactiveFrame.maxX,
                        inactiveFrame.minX - activeFrame.maxX
                    )

                    XCTAssertFalse(
                        activeFrame.intersects(inactiveFrame),
                        "\(inactiveMode) overlaps \(activeMode) active pill at \(availableWidth)"
                    )
                    XCTAssertGreaterThanOrEqual(gap, ModeSwitcherLayoutPolicy.modeSwitcherSpacing)
                }
            }
        }
    }

    func testInactiveStoneFramesRespectActiveModeAreas() {
        let availableWidth = CGFloat(760)

        for activeMode in LauncherMode.ordered {
            let activeIndex = LauncherMode.ordered.firstIndex(of: activeMode)!
            let activeFrame = ModeSwitcherLayoutPolicy.activePillFrame(
                for: activeMode,
                availableWidth: availableWidth
            )

            for (modeIndex, mode) in LauncherMode.ordered.enumerated() where mode != activeMode {
                let frame = ModeSwitcherLayoutPolicy.inactiveStoneFrame(
                    for: mode,
                    activeMode: activeMode,
                    availableWidth: availableWidth
                )

                if modeIndex < activeIndex {
                    XCTAssertEqual(
                        frame,
                        ModeSwitcherLayoutPolicy.inactiveStoneFrame(for: mode, availableWidth: availableWidth)
                    )
                } else {
                    let trailingIndex = modeIndex - activeIndex - 1
                    let expectedMinX = activeFrame.maxX
                        + ModeSwitcherLayoutPolicy.modeSwitcherSpacing
                        + CGFloat(trailingIndex)
                            * (ModeSwitcherLayoutPolicy.inactiveStoneSlotWidth + ModeSwitcherLayoutPolicy.modeSwitcherSpacing)
                    XCTAssertEqual(frame.minX, expectedMinX)
                }
            }
        }
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

    private func assertActivePillExpandsFromTrailingStoneEdge(
        mode: LauncherMode,
        availableWidth: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let finalFrame = ModeSwitcherLayoutPolicy.activePillFrame(
            for: mode,
            availableWidth: availableWidth
        )
        let startFrame = ModeSwitcherLayoutPolicy.activePillFrame(
            for: mode,
            availableWidth: availableWidth,
            expansionProgress: 0
        )
        let halfwayFrame = ModeSwitcherLayoutPolicy.activePillFrame(
            for: mode,
            availableWidth: availableWidth,
            expansionProgress: 0.5
        )

        XCTAssertEqual(startFrame.maxX, finalFrame.maxX, file: file, line: line)
        XCTAssertEqual(startFrame.width, ModeSwitcherLayoutPolicy.inactiveStoneSlotWidth, file: file, line: line)
        XCTAssertEqual(halfwayFrame.maxX, finalFrame.maxX, file: file, line: line)
        XCTAssertGreaterThan(halfwayFrame.width, startFrame.width, file: file, line: line)
        XCTAssertLessThan(halfwayFrame.width, finalFrame.width, file: file, line: line)
        XCTAssertEqual(
            ModeSwitcherLayoutPolicy.activePillFrame(
                for: mode,
                availableWidth: availableWidth,
                expansionProgress: 1
            ),
            finalFrame,
            file: file,
            line: line
        )
    }

}
