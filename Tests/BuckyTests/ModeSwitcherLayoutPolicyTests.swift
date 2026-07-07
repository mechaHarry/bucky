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
        XCTAssertEqual(shortPathWidth, 274)
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
        XCTAssertGreaterThan(
            ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress: false, isShowingCalculatorResult: true),
            ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress: false)
        )
        XCTAssertGreaterThan(ModeSwitcherLayoutPolicy.activeTextPillVerticalInset, 0)
        XCTAssertLessThan(ModeSwitcherLayoutPolicy.activeTextPillControlHeight, ModeSwitcherLayoutPolicy.activePillHeight)
    }

    func testTextInputModesUseSharedTextPillLayout() {
        XCTAssertEqual(LauncherMode.ordered.filter(\.acceptsTextInput), [
            .applications,
            .dictionary,
            .agenda
        ])
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .applications))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .dictionary))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .files))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .agenda))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .applications))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .dictionary))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .files))
        XCTAssertFalse(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .agenda))
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
        XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset("))
        XCTAssertTrue(source.contains("isShowingProgress: isShowingProgress"))
        XCTAssertTrue(source.contains("isShowingCalculatorResult: isShowingCalculatorResult"))
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

    func testCalculatorResultFeedbackRendersRightSideLayerAndGlow() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("@State private var calculatorGlowProgress: CGFloat = 0"))
        XCTAssertTrue(source.contains("let calculatorResultFeedback = model.isApplicationCalculatorActive ? model.calculatorResultFeedback : nil"))
        XCTAssertTrue(source.contains("CalculatorResultFeedbackLayer(feedback: calculatorResultFeedback, tint: modeTint)"))
        XCTAssertTrue(source.contains("CalculatorResultGlowBorder(tint: modeTint, progress: calculatorGlowProgress)"))
        XCTAssertTrue(source.contains("Text(\"= \\(feedback.result)\""))
        XCTAssertTrue(source.contains(".monospacedDigit()"))
        XCTAssertTrue(source.contains("Rectangle()\n                        .frame(width: max(0, proxy.size.width * progress))"))
        XCTAssertTrue(source.contains("isShowingCalculatorResult: calculatorResultFeedback != nil"))
    }

    func testCalculatorStoneIsRemovedFromModeSwitcher() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("ForEach(LauncherMode.ordered, id: \\.self)"))
        XCTAssertFalse(source.contains("case .calculator"))
        XCTAssertFalse(source.contains("123.rectangle.fill"))
        XCTAssertFalse(source.contains("Command+2"))
    }

    func testDictionaryPreviewUsesReadableSectionsAndCommonsImageFlow() throws {
        let source = try launcherViewSource()

        XCTAssertTrue(source.contains("DictionaryDefinitionVariantCard("))
        XCTAssertTrue(source.contains("imageTerm: section.imageSearchTerm(for: previewTerm)"))
        XCTAssertTrue(source.contains("imageSearchURL: DictionaryDefinitionPreview.commonsImageSearchURL(for: section.imageSearchTerm(for: previewTerm))"))
        XCTAssertTrue(source.contains("DictionaryImageFlowSection(term: imageTerm, imageSearchURL: imageSearchURL, tint: tint)"))
        XCTAssertTrue(source.contains("DictionaryImageCarousel(imageURLs: imageURLs, tint: tint)"))
        XCTAssertTrue(source.contains("DictionaryRemoteImageView(url: url)"))
        XCTAssertTrue(source.contains("CommonsImageSearchClient.shared.imageURLs(for: term)"))
        XCTAssertTrue(source.contains("DictionaryFormattedDefinitionView(\n                    previewTerm: preview.term"))
        XCTAssertTrue(source.contains(".italic()"))
        XCTAssertTrue(source.contains("ForEach(section.items)"))
        XCTAssertTrue(source.contains("Divider().opacity(0.42)"))
        XCTAssertTrue(source.contains("Label(\"Wikimedia Commons\", systemImage: \"photo.on.rectangle.angled\")"))
        XCTAssertTrue(source.contains(".frame(height: DictionaryPreviewLayout.imageFlowHeight)"))
        XCTAssertFalse(source.contains("GoogleImageSearchClient"))
        XCTAssertFalse(source.contains("GoogleImageSearchHTMLParser"))
        XCTAssertFalse(source.contains("WKWebView"))
        XCTAssertFalse(source.contains("DictionaryImageSearchWebPreview"))
    }

    func testDictionaryDefinitionFormatterSplitsHeadingsDefinitionsAndExamples() {
        let sections = DictionaryDefinitionFormatter.sections(
            from: "apple | noun The round fruit of a tree of the rose family. Example: She sliced an apple for breakfast. \"An apple a day.\"",
            term: "apple"
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "noun")
        XCTAssertEqual(
            sections[0].items,
            [
                DictionaryDefinitionSection.Item(kind: .definition, text: "The round fruit of a tree of the rose family."),
                DictionaryDefinitionSection.Item(kind: .example, text: "She sliced an apple for breakfast."),
                DictionaryDefinitionSection.Item(kind: .example, text: "An apple a day.")
            ]
        )
    }

    func testDictionaryDefinitionFormatterSplitsCompactDictionaryOutputIntoReadableSections() {
        let sections = DictionaryDefinitionFormatter.sections(
            from: """
            thrash | THraSH | verb [with object] 1 beat (a person or animal) repeatedly and violently with a stick or whip: she thrashed him across the head and shoulders. • hit (something) hard and repeatedly: the wind screeched and the mast thrashed the deck. 2 [no object] move in a violent and convulsive way: he lay on the ground thrashing around in pain | [with object] : she thrashed her arms, attempting to swim. noun 1 [usually in singular] a violent or noisy movement, typically involving hitting something repeatedly: the thrash of the waves. PHRASAL VERBS thrash out (thrash something out, thrash out something) discuss something frankly and thoroughly, especially to reach a decision: it is essential that conflicting views are heard and thrashed out. ORIGIN Old English, variant of thresh (an early sense).
            """,
            term: "thrash"
        )

        XCTAssertEqual(sections.map(\.title), ["verb [with object]", "noun", "PHRASAL VERBS", "ORIGIN"])
        XCTAssertEqual(sections[0].items[0].marker, "1")
        XCTAssertEqual(sections[0].items[0].text, "beat (a person or animal) repeatedly and violently with a stick or whip:")
        XCTAssertEqual(sections[0].items[1].kind, .example)
        XCTAssertEqual(sections[0].items[1].text, "she thrashed him across the head and shoulders.")
        XCTAssertEqual(sections[0].items[2].kind, .subdefinition)
        XCTAssertEqual(sections[0].items[2].text, "hit (something) hard and repeatedly:")
        XCTAssertEqual(sections[2].items[0].kind, .definition)
        XCTAssertTrue(sections[2].items[0].text.hasPrefix("thrash out"))
        XCTAssertEqual(sections[3].items[0].kind, .note)
    }

    func testDictionaryDefinitionSectionsCreateVariantSpecificImageTerms() {
        let sections = DictionaryDefinitionFormatter.sections(
            from: "thrash | verb 1 beat repeatedly. noun 1 a violent movement. ORIGIN Old English.",
            term: "thrash"
        )

        XCTAssertEqual(sections.map { $0.imageSearchTerm(for: "thrash") }, [
            "thrash verb",
            "thrash noun",
            "thrash origin"
        ])
        XCTAssertEqual(
            DictionaryDefinitionPreview.commonsImageSearchURL(for: "thrash noun")?.absoluteString,
            "https://commons.wikimedia.org/w/index.php?search=file:thrash%20noun&title=Special:MediaSearch&type=image"
        )
    }

    func testCommonsImageSearchResponseExtractsDedupedThumbnailURLs() throws {
        let data = """
        {
          "query": {
            "pages": {
              "10": {
                "pageid": 10,
                "title": "File:One.jpg",
                "imageinfo": [
                  { "thumburl": "https://upload.wikimedia.org/wikipedia/commons/thumb/one.jpg/320px-one.jpg" }
                ]
              },
              "11": {
                "pageid": 11,
                "title": "File:Duplicate.jpg",
                "imageinfo": [
                  { "thumburl": "https://upload.wikimedia.org/wikipedia/commons/thumb/one.jpg/320px-one.jpg" }
                ]
              },
              "12": {
                "pageid": 12,
                "title": "File:Two.jpg",
                "imageinfo": [
                  { "thumburl": "https://upload.wikimedia.org/wikipedia/commons/thumb/two.jpg/320px-two.jpg" }
                ]
              }
            }
          }
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            try CommonsImageSearchResponseParser.imageURLs(from: data, limit: 4).map(\.absoluteString),
            [
                "https://upload.wikimedia.org/wikipedia/commons/thumb/one.jpg/320px-one.jpg",
                "https://upload.wikimedia.org/wikipedia/commons/thumb/two.jpg/320px-two.jpg"
            ]
        )
    }

    func testCommonsImageSearchRequestUsesNoKeyCommonsAPI() throws {
        let url = try XCTUnwrap(CommonsImageSearchClient.searchURL(for: "thrash", limit: 12, thumbnailWidth: 320))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "commons.wikimedia.org")
        XCTAssertEqual(queryItems["action"], "query")
        XCTAssertEqual(queryItems["generator"], "search")
        XCTAssertEqual(queryItems["gsrnamespace"], "6")
        XCTAssertEqual(queryItems["prop"], "imageinfo")
        XCTAssertEqual(queryItems["iiprop"], "url")
        XCTAssertEqual(queryItems["iiurlwidth"], "320")
        XCTAssertNil(queryItems["api_key"])
    }

    func testLauncherSearchFocusRetriesWhenWindowBecomesKey() throws {
        let source = try launcherViewSource()
        let modelSource = try launcherModelSource()
        let controllerSource = try launcherWindowControllerSource()

        XCTAssertTrue(modelSource.contains("@Published var isWindowKey = false"))
        XCTAssertTrue(source.contains(".onChange(of: model.isWindowKey)"))
        XCTAssertTrue(source.contains("if isWindowKey {\n                synchronizeSearchFocus()\n            }"))
        XCTAssertTrue(controllerSource.contains("func windowDidBecomeKey(_ notification: Notification) {\n        model.setWindowKeyState(true)\n    }"))
        XCTAssertEqual(controllerSource.components(separatedBy: "model.setWindowKeyState(true)").count - 1, 1)
    }

    func testFilesPathMarqueeUsesFixedPathWidthInsidePill() {
        let pathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
            in: 420,
            path: "/Users/test/Very Long Folder Name/Deep/File.txt"
        )

        XCTAssertEqual(ModeSwitcherLayoutPolicy.filesPathMarqueeWidth(in: 420), pathWidth)
        XCTAssertLessThan(pathWidth, 420)
    }

    func testFilesPillExposesPersistentFoldersFirstToggle() throws {
        let source = try modeSwitcherSource()

        XCTAssertTrue(source.contains("private var foldersFirstToggle: some View"))
        XCTAssertTrue(source.contains("model.activeFileBrowserModel?.foldersFirst ?? false"))
        XCTAssertTrue(source.contains("model.activeFileBrowserModel?.setFoldersFirst($0)"))
        XCTAssertTrue(source.contains(".toggleStyle(.button)"))
        XCTAssertTrue(source.contains(".help(\"Folders first\")"))
        XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.filesFoldersFirstToggleWidth"))
    }

    private func modeSwitcherSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func launcherViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func launcherModelSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func launcherWindowControllerSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
